import AppKit

extension AppDelegate {
    func decideAutoSwitch() {
        let snapshot = popover.model.snapshot
        let world = AutoSwitchWorld(
            readings: usage.readings,
            wearing: snapshot.wearing?.id,
            eligible: AutoSwitchEngine.eligible(in: snapshot.rows)
        )
        let outcome = AutoSwitchEngine.outcome(policy: settings.autoSwitch, world: world, now: Date())
        if case .hold = outcome.decision {
            noteHolding(AutoSwitchEngine.reasonForHolding(policy: settings.autoSwitch, world: world))
            return
        }
        lastAutoSwitchHold = nil
        if case .nowhereToGo(let limit) = outcome.decision {
            Journal.log("autoSwitch.nowhereToGo", [
                "limit": limit.rawValue,
                "wearing": snapshot.wearing?.id ?? "-",
            ])
            return
        }
        guard let id = outcome.wearsHat else { return }
        performAutoSwitch(to: id, outcome: outcome, titles: { snapshot.title(of: $0) })
    }

    private func performAutoSwitch(
        to id: String,
        outcome: AutoSwitchOutcome,
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
                "limit": outcome.record?.limit.rawValue ?? "-",
                "to": id,
            ])
            if let notice = AutoSwitchEngine.notice(for: outcome, title: titles) {
                Notifier.post(title: notice.0, body: notice.1)
            }
            syncWithWorld(reportingErrors: false)
            usage.poll(hatsForUsage())
        } catch {
            Journal.log("autoSwitch.failed", ["to": id, "reason": error.localizedDescription])
            redrawAfterTheLiveSlotMayHaveMoved()
        }
    }

    func noteHolding(_ reason: AutoSwitchHold?) {
        guard lastAutoSwitchHold != reason else { return }
        lastAutoSwitchHold = reason
        guard let reason else { return }
        Journal.log("autoSwitch.holding", ["reason": reason.rawValue])
    }

    func updateAutoSwitch(_ policy: AutoSwitchPolicy) {
        settings.autoSwitch = policy
        saveSettings()
        if policy.wantsNotifications { Notifier.askOnce() }
        redraw()
        decideAutoSwitch()
    }

    func switchBack() {
        guard let record = settings.autoSwitchRecord else { return }
        settings.autoSwitchRecord = nil
        saveSettings()
        wear(record.from)
    }
}
