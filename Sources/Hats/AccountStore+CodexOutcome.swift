import Foundation

extension AccountStore {
    func noteCodexWear(_ id: String, outcome: CodexWorn, renewed: [CodexRenewed], at now: Date = Date()) throws {
        if case .worn(_, let outgoing?, let parked?) = outcome {
            noteCodexLogin(outgoing, login: parked, signedIn: false)
        }
        noteCodexRenewals(renewed, at: now)
        try noteCodexWorn(id, at: now)
    }

    func noteCodexRelogin(_ id: String, login data: Data, stored: Bool, outcome: CodexWorn?, at now: Date = Date()) {
        if stored { noteCodexLogin(id, login: data, signedIn: true, at: now) }
        if case .worn(_, let outgoing?, let parked?)? = outcome {
            noteCodexLogin(outgoing, login: parked, signedIn: false)
        }
    }
}
