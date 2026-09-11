import Foundation

enum AuthObservation {
    struct Change: Equatable {
        let id: String
        let refusedAt: Date?
        let display: String

        var journalEvent: String { refusedAt == nil ? "auth.acceptedAgain" : "auth.refused" }
    }

    static func changes(
        in accounts: [Account],
        refused: Set<String>,
        accepted: Set<String>,
        at now: Date
    ) -> [Change] {
        accounts.compactMap { account in
            if refused.contains(account.id), account.authRefusedAt == nil {
                return Change(id: account.id, refusedAt: now, display: account.display)
            }
            if accepted.contains(account.id), account.authRefusedAt != nil {
                return Change(id: account.id, refusedAt: nil, display: account.display)
            }

            return nil
        }
    }
}
