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
            let warning = AutoSwitchWarning.of(
                decision: outcome.decision,
                holding: holding,
                blindness: world.blindness
            )
            noteTheUsageCannotBeRead(warning, on: snapshot)
        }
        if case .hold = outcome.decision {
            lastAutoSwitchNowhere.clear()
            noteHolding(holding, missedPolls: world.blindness.missedPolls)
            return
        }
        lastAutoSwitchHold = nil
        if case .nowhereToGo(let limit) = outcome.decision {
            noteNowhereToGo(limit, wearing: snapshot.wearing?.id)
            return
        }
        lastAutoSwitchNowhere.clear()
        guard let id = outcome.wearsHat else { return }
        performAutoSwitch(to: id, outcome: outcome, at: now, titles: { snapshot.title(of: $0) })
    }

    private func noteTheUsageCannotBeRead(_ warning: AutoSwitchWarning?, on snapshot: HatsSnapshot) {
        if theWornUsageCannotBeRead != (warning != nil) {
            theWornUsageCannotBeRead = warning != nil
            redraw()
        }
        guard lastBlindWarning != warning else { return }
        lastBlindWarning = warning
        guard let warning, settings.autoSwitch.wantsNotifications else { return }
        let text = warning.text(hat: snapshot.wearing?.title ?? "this hat")
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

    func noteNowhereToGo(_ limit: UsageLimit?, wearing: String?) {
        let reason = limit?.rawValue ?? AutoSwitchCause.usageCouldNotBeRead.rawValue
        guard lastAutoSwitchNowhere.shouldWrite(reason) else { return }
        Journal.log("autoSwitch.nowhereToGo", ["limit": reason, "wearing": wearing ?? "-"])
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
        if switchedOn { forgetTheBlindness() }
        decideAutoSwitch(from: .theToggleChanged)
        redraw()
    }

    func forgetTheBlindness() {
        usage.forgetTheMissedPolls()
        theWornUsageCannotBeRead = false
        lastBlindWarning = nil
    }

    func switchBack() {
        guard let record = settings.autoSwitchRecord else { return }
        settings.autoSwitchRecord = nil
        saveSettings()
        wear(record.from)
    }
}
