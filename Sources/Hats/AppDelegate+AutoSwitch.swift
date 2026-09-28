import AppKit

extension AppDelegate {
    func decideAutoSwitch(from call: AutoSwitchCall) {
        let snapshot = popover.model.snapshot
        let world = AutoSwitchWorld.of(
            snapshot: snapshot,
            readings: usage.readings,
            missed: usage.missed,
            fresh: usage.freshInTheLastPoll,
            from: call
        )
        let now = Date()
        let outcome = AutoSwitchEngine.outcome(policy: settings.autoSwitch, world: world, now: now)
        let holding = AutoSwitchEngine.reasonForHolding(policy: settings.autoSwitch, world: world, at: now)
        if world.blindness.landedAPoll {
            pollsLanded += 1
            let warning = AutoSwitchWarning.of(
                decision: outcome.decision,
                holding: holding,
                blindness: world.blindness
            )
            noteTheWarning(warning, on: snapshot, at: now)
        }
        if case .hold = outcome.decision {
            lastAutoSwitchNowhere.clear()
            noteHolding(holding, missedPolls: world.blindness.missedPolls)
            return
        }
        lastAutoSwitchHold = nil
        if case .nowhereToGo(let deadEnd) = outcome.decision {
            noteNowhereToGo(deadEnd, wearing: snapshot.wearing?.id)
            return
        }
        lastAutoSwitchNowhere.clear()
        guard let id = outcome.wearsHat else { return }
        performAutoSwitch(to: id, outcome: outcome, at: now, titles: { snapshot.title(of: $0) })
    }

    private func noteTheWarning(_ warning: AutoSwitchWarning?, on snapshot: HatsSnapshot, at now: Date) {
        let change = AutoSwitchWarningChange.of(
            warning,
            held: lastAutoSwitchWarning,
            announced: lastAnnouncedWarning,
            notifies: settings.autoSwitch.wantsNotifications
        )
        lastAutoSwitchWarning = change.keeps
        lastAnnouncedWarning = change.remembers
        if change.redraws { redraw() }
        guard change.announces, let warning else { return }
        let text = warning.text(hat: snapshot.wearing?.title ?? "this hat", now: now)
        Notifier.post(title: text.0, body: text.1)
    }

    private func performAutoSwitch(
        to id: String,
        outcome: AutoSwitchOutcome,
        at now: Date,
        titles: (String) -> String
    ) {
        do {
            try store.activate(
                id,
                meters: wornMetersForTheJournal(),
                targetMeters: metersForTheJournal(of: id)
            )
            settings.autoSwitchRecord = outcome.record
            saveSettings()
            Journal.log("autoSwitch.done", [
                "limit": outcome.record?.journalReason ?? "-",
                "to": id,
            ])
            let seen = outcome.record.flatMap { usage.readAt[$0.from] }
            let notice = AutoSwitchEngine.notice(
                for: outcome,
                lastSeen: seen.map { now.timeIntervalSince($0) },
                title: titles
            )
            if let notice { Notifier.post(title: notice.0, body: notice.1) }
            syncWithWorld(reportingErrors: false)
            usage.poll(hatsForUsage())
        } catch {
            Journal.log("autoSwitch.failed", ["to": id, "reason": error.localizedDescription])
            redrawAfterTheLiveSlotMayHaveMoved()
        }
    }

    func noteNowhereToGo(_ deadEnd: AutoSwitchDeadEnd, wearing: String?) {
        let line = NowhereToGoLine.of(deadEnd)
        guard lastAutoSwitchNowhere.shouldWrite(line.key) else { return }
        Journal.log("autoSwitch.nowhereToGo", [
            "limit": line.limit,
            "reason": line.reason,
            "wearing": wearing ?? "-",
        ])
    }

    func noteHolding(_ reason: AutoSwitchHold?, missedPolls: Int = 0) {
        guard lastAutoSwitchHold != reason else { return }
        lastAutoSwitchHold = reason
        guard let reason, reason.isWorthAJournalLine else { return }
        let meter = wornMetersForTheJournal()
        Journal.log("autoSwitch.holding", [
            "reason": reason.rawValue,
            "missedPolls": String(missedPolls),
            "usage": meter.line,
            "usageAge": meter.age,
        ])
    }

    func updateAutoSwitch(_ policy: AutoSwitchPolicy) {
        let switchedOn = policy.hasJustBeenTurnedOn(from: settings.autoSwitch)
        settings.autoSwitch = policy
        saveSettings()
        if policy.wantsNotifications { Notifier.askOnce() }
        if switchedOn { forgetWhatTheSwitchHasSeen() }
        decideAutoSwitch(from: .theToggleChanged)
        redraw()
        if switchedOn { usage.poll(hatsForUsage()) }
    }

    func forgetWhatTheSwitchHasSeen() {
        usage.forgetTheMissedPolls()
        lastAutoSwitchWarning = nil
        lastAnnouncedWarning = nil
    }

    func switchBack() {
        guard let record = settings.autoSwitchRecord else { return }
        settings.autoSwitchRecord = nil
        saveSettings()
        wear(record.from)
    }
}
