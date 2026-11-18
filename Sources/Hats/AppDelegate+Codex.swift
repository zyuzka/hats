import AppKit

extension AppDelegate {
    func startTheCodexHats() {
        noticeTheWornCodexHat()
        listenToTheCodexGateway()
        syncTheCodexGateway()
        codex.start(every: usage.interval) { [weak self] in
            self?.noticeTheWornCodexHat()
            self?.renewTheParkedCodexHats()
            self?.syncTheCodexGateway()
            self?.renewTheWornCodexHat()
        }
        codex.startReadingUsage(every: CodexUsagePoll.interval) { [weak self] in self?.readTheCodexUsage() }
    }

    func readTheCodexUsage() {
        codex.usage.poll(store.codexTickets, worn: store.codexActiveID) { [weak self] in self?.redraw() }
    }

    func noticeTheWornCodexHat() {
        do {
            store.noticeCodexLive(try CodexHome.real.readLive())
        } catch {
            Journal.log("codex.liveUnread", ["reason": error.localizedDescription])
        }
        codex.desk.noteWorn(store.codexActiveID)
    }

    func renewTheParkedCodexHats(forcing: Set<String> = []) {
        codex.desk.renew(store.codexTickets, forcing: forcing) { [weak self] results in
            guard let self, !results.isEmpty else { return }
            self.store.noteCodexRenewals(results)
            self.redraw()
        }
    }

    func noteTheLostCodexAnswers() {
        let lost = codex.desk.heldIDs()
        for id in lost { Journal.log("codex.renew.lost", ["hat": String(id.prefix(8))]) }
        store.noteCodexRenewals(lost.map { .needsSignIn($0, "the renewed login was not saved before Hats quit") })
    }

    func codexRows(chromeNames: [String: String]) -> [HatRowState] {
        ClaudeDoors.codexRows(
            store.accounts,
            worn: store.codexActiveID,
            usage: codex.usage.book,
            chromeNames: chromeNames
        )
    }

    func wearCodex(_ id: String) {
        guard let hat = store.codexHats.first(where: { $0.id == id }),
              let ticket = store.codexTicket(hat) else { return }
        changing = id
        redraw()
        codex.desk.wear(ticket, among: store.codexTickets) { [weak self] result, renewed in
            guard let self else { return }
            self.changing = nil
            switch result {
            case .success(let worn):
                do {
                    try self.store.noteCodexWear(id, outcome: worn, renewed: renewed)
                } catch {
                    HatDialogs.present(error)
                }
            case .failure(let error):
                HatDialogs.present(error)
            }
            self.redraw()
        }
    }
}
