import Foundation

struct CodexNewHat {
    let name: String?
    let email: String
    let browser: BrowserChoice?
}

extension AccountStore {
    func codexTicket(_ hat: Account, at now: Date = Date()) -> CodexTicket? {
        guard hat.wornTool == .codex, let owner = hat.codexOwner else { return nil }
        return CodexTicket(id: hat.id, owner: owner, title: hat.title, needsSignIn: hat.blocker(at: now) != nil)
    }

    var codexTickets: [CodexTicket] { codexHats.compactMap { codexTicket($0) } }

    func checkCodexLogin(_ data: Data, expecting email: String) throws -> CodexIdentity {
        guard let auth = CodexAuth(data: data) else { throw CodexError.notChatGPT }
        switch auth.problem {
        case .notChatGPT, .notJSON: throw CodexError.notChatGPT
        case .noTokens, .noOwner: throw CodexError.noOwner
        case nil: break
        }
        guard let identity = auth.identity else { throw CodexError.noOwner }
        guard let said = identity.email, Account.sameAddress(said, email) else {
            throw CodexError.wrongAccount(expected: email, actual: identity.email ?? "an account without an address")
        }

        return identity
    }

    func addCodexHat(_ wanted: CodexNewHat, login data: Data, isLive: Bool, at now: Date = Date()) throws -> Account {
        try requireReadableIndex()
        guard let address = Account.storableAddress(wanted.email) else { throw SwitchError.blankAddress }
        let identity = try checkCodexLogin(data, expecting: address)
        if let same = codexHats.first(where: { $0.codexOwner == identity.owner }) {
            throw CodexError.duplicateOwner(same.title)
        }
        var hat = Account(id: UUID().uuidString, email: address, browser: wanted.browser, name: wanted.name)
        hat.tool = .codex
        try keychain.writeVerified(data, to: Slot.codexParked(hat.id), label: hat.title)
        hat = hat.withCodexLogin(data, identity: identity, at: now)
        do {
            try commit { accounts, codexActiveID in
                accounts.append(hat)
                if isLive { codexActiveID = hat.id }
            }
        } catch {
            try? keychain.delete(Slot.codexParked(hat.id))
            throw error
        }
        Journal.log("codex.hat.added", [
            "hat": String(hat.id.prefix(8)),
            "plan": identity.plan ?? "-",
            "live": String(isLive),
            "payload": Journal.fingerprint(data),
        ])

        return hat
    }

    func checkCodexRelogin(_ id: String, login data: Data) throws -> CodexTicket {
        guard let hat = codexHats.first(where: { $0.id == id }), let owner = hat.codexOwner else {
            throw CodexError.notACodexHat(id)
        }
        let identity = try checkCodexLogin(data, expecting: hat.email)
        guard identity.owner == owner else { throw CodexError.notTheSameOwner(hat.title) }

        return CodexTicket(id: id, owner: owner, title: hat.title, needsSignIn: false)
    }

    func noteCodexLogin(_ id: String, login data: Data, signedIn: Bool, at now: Date = Date()) {
        guard let identity = CodexAuth(data: data)?.identity else { return }
        record("a Codex login") { accounts, _ in
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            accounts[index] = accounts[index].withCodexLogin(data, identity: identity, at: signedIn ? now : nil)
        }
    }

    func noticeCodexLive(_ live: Data?) {
        let owner = live.flatMap { CodexAuth(data: $0)?.owner }
        let worn = owner.flatMap { owner in codexHats.first { $0.codexOwner == owner }?.id }
        guard worn != codexActiveID else { return }
        Journal.log("codex.wornNoticed", ["hat": worn.map { String($0.prefix(8)) } ?? "none"])
        record("the worn Codex hat") { _, codexActiveID in codexActiveID = worn }
    }

    func noteCodexWorn(_ id: String, at now: Date = Date()) throws {
        guard codexHats.contains(where: { $0.id == id }) else { return }
        try commit { accounts, codexActiveID in
            codexActiveID = id
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
            accounts[index].lastActivatedAt = now
        }
    }

    func noteCodexRenewals(_ results: [CodexRenewed], at now: Date = Date()) {
        for result in results {
            switch result {
            case .renewed(let id, let data):
                noteCodexLogin(id, login: data, signedIn: false)
            case .needsSignIn(let id, _):
                record("a refused Codex login") { accounts, _ in
                    guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
                    accounts[index].authRefusedAt = now
                }
            case .failed, .notSaved:
                continue
            }
        }
    }

    func record(_ what: String, _ change: (inout [Account], inout String?) -> Void) {
        do {
            try commit(change)
        } catch {
            Journal.log("codex.notRecorded", ["what": what, "reason": error.localizedDescription])
        }
    }
}

extension Account {
    func withCodexLogin(_ data: Data, identity: CodexIdentity, at signedIn: Date?) -> Account {
        var hat = self
        hat.hasStoredCredentials = true
        hat.codexOwner = identity.owner
        hat.codexPlan = identity.plan ?? hat.codexPlan
        hat.accessExpiresAt = CodexAuth(data: data)?.accessExpiry
        if let signedIn {
            hat.lastLoginAt = signedIn
            hat.authRefusedAt = nil
        }

        return hat
    }
}
