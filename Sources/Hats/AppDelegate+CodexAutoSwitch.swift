import AppKit

struct CodexAutoSwitchMemory {
    var lastHold: AutoSwitchHold?
    var lastNowhere = NoteOnChange()
    var isWearing = false
    var failures = CodexAutoSwitchFailures()
    var lastWarning: AutoSwitchWarning?
    var lastAnnounced: AutoSwitchWarning?
}

extension AppDelegate {
    func decideEverySwitch(from call: AutoSwitchCall) {
        decideAutoSwitch(from: call)
        decideCodexAutoSwitch(from: call)
    }

    func decideCodexAutoSwitch(from call: AutoSwitchCall) {
        guard !codexSwitch.isWearing else { return }
        let rows = codexRows(chromeNames: [:])
        let policy = settings.codexAutoSwitch
        let now = Date()
        let outcome = CodexAutoSwitch.outcome(policy: policy, rows: rows, at: now)
        noteTheCodexWarning(CodexAutoSwitch.warning(for: outcome, rows: rows), rows: rows, at: now)
        switch outcome.decision {
        case .hold:
            codexSwitch.lastNowhere.clear()
            noteCodexHolding(CodexAutoSwitch.reasonForHolding(policy: policy, rows: rows, at: now), call: call)
        case .nowhereToGo(let deadEnd):
            codexSwitch.lastHold = nil
            noteCodexNowhereToGo(deadEnd, wearing: rows.first(where: \.isWearing)?.id)
        case .fire, .fireBlind:
            codexSwitch.lastHold = nil
            codexSwitch.lastNowhere.clear()
            guard let record = outcome.record,
                  codexSwitch.failures.allows(from: record.from, to: record.to) else { return }
            let titles = Dictionary(rows.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
            performCodexAutoSwitch(record, outcome: outcome, titles: { titles[$0] ?? $0 })
        }
    }

    private func performCodexAutoSwitch(
        _ record: AutoSwitchRecord,
        outcome: AutoSwitchOutcome,
        titles: @escaping (String) -> String
    ) {
        let line = ["from": String(record.from.prefix(8)), "to": String(record.to.prefix(8))]
        guard let hat = store.codexHats.first(where: { $0.id == record.to }),
              let ticket = store.codexTicket(hat) else {
            return noteTheCodexFailure(record, reason: "the hat is gone", line: line)
        }
        codexSwitch.isWearing = true
        codex.desk.wear(ticket, insteadOf: record.from, among: store.codexTickets) { [weak self] result in
            guard let self else { return }
            self.codexSwitch.isWearing = false
            switch result {
            case .moved, .worn(.alreadyWorn, _):
                Journal.log("codexAutoSwitch.cancelled", line.merging(["reason": "theWornHatChanged"]) { $1 })
            case .failed(let reason):
                self.noteTheCodexFailure(record, reason: reason, line: line)
            case .worn(let worn, let renewed):
                self.noteTheCodexAutoWear(worn, renewed: renewed, record: record, line: line)
                self.readTheCodexUsage()
                if let notice = AutoSwitchEngine.notice(for: outcome, title: titles) {
                    Notifier.post(title: notice.0, body: notice.1)
                }
            }
            self.redraw()
        }
    }

    private func noteTheCodexFailure(_ record: AutoSwitchRecord, reason: String, line: [String: String]) {
        guard codexSwitch.failures.shouldWriteAFailure(from: record.from, to: record.to, reason: reason) else { return }
        Journal.log("codexAutoSwitch.failed", line.merging(["reason": reason]) { $1 })
    }

    private func noteTheCodexWarning(_ warning: AutoSwitchWarning?, rows: [HatRowState], at now: Date) {
        let change = AutoSwitchWarningChange.of(
            warning,
            held: codexSwitch.lastWarning,
            announced: codexSwitch.lastAnnounced,
            notifies: settings.codexAutoSwitch.wantsNotifications
        )
        codexSwitch.lastWarning = change.keeps
        codexSwitch.lastAnnounced = change.remembers
        if change.redraws { redraw() }
        guard change.announces, let warning else { return }
        let text = warning.text(hat: rows.first(where: \.isWearing)?.title ?? "this hat", now: now)
        Notifier.post(title: text.0, body: text.1)
    }

    private func noteTheCodexAutoWear(
        _ worn: CodexWorn,
        renewed: [CodexRenewed],
        record: AutoSwitchRecord,
        line: [String: String]
    ) {
        do {
            try store.noteCodexWear(record.to, outcome: worn, renewed: renewed)
        } catch {
            Journal.log("codexAutoSwitch.wearNotRecorded", line.merging(["reason": error.localizedDescription]) { $1 })
        }
        codexSwitch.failures.succeeded()
        settings.codexAutoSwitchRecord = record
        saveSettings()
        Journal.log("codexAutoSwitch.done", line.merging(["limit": record.journalReason]) { $1 })
    }

    private func noteCodexNowhereToGo(_ deadEnd: AutoSwitchDeadEnd, wearing: String?) {
        let line = NowhereToGoLine.of(deadEnd)
        guard codexSwitch.lastNowhere.shouldWrite(line.key) else { return }
        Journal.log("codexAutoSwitch.nowhereToGo", [
            "limit": line.limit,
            "reason": line.reason,
            "wearing": wearing.map { String($0.prefix(8)) } ?? "-",
        ])
    }

    private func noteCodexHolding(_ reason: AutoSwitchHold?, call: AutoSwitchCall) {
        guard codexSwitch.lastHold != reason else { return }
        codexSwitch.lastHold = reason
        guard let reason, reason.isWorthAJournalLine else { return }
        Journal.log("codexAutoSwitch.holding", ["reason": reason.rawValue, "on": "\(call)"])
    }

    func updateCodexAutoSwitch(_ policy: AutoSwitchPolicy) {
        let switchedOn = policy.hasJustBeenTurnedOn(from: settings.codexAutoSwitch)
        settings.codexAutoSwitch = policy
        saveSettings()
        if policy.wantsNotifications { Notifier.askOnce() }
        decideCodexAutoSwitch(from: .theToggleChanged)
        redraw()
        if switchedOn { readTheCodexUsage() }
    }

    func switchBackCodex() {
        guard let record = settings.codexAutoSwitchRecord else { return }
        dropTheCodexSwitchBack()
        wearCodex(record.from)
    }

    func dropTheCodexSwitchBack() {
        codexSwitch.lastWarning = nil
        codexSwitch.lastAnnounced = nil
        guard settings.codexAutoSwitchRecord != nil else { return }
        settings.codexAutoSwitchRecord = nil
        saveSettings()
    }
}
