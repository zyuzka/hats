import Foundation

final class AccountStore {
    let osAccount: String

    private(set) var accounts: [Account] = []
    private(set) var activeID: String?

    init(osAccount: String = NSUserName()) {
        self.osAccount = osAccount
        file = AccountsFile(osAccount: osAccount)
        load()
    }

    private let file: AccountsFile

    private typealias Snapshot = (accounts: [Account], activeID: String?)

    private var snapshot: Snapshot { (accounts, activeID) }

    private(set) var hasUnsavedChanges = false

    let identityQueue = DispatchQueue(label: "hats.identity-from-token")

    var fetchingTokenIdentity: (String) -> ProfileFetch = { ProfileFetcher.fetch(token: $0) }

    private func recordCompletedChange(_ what: String) throws {
        do {
            try save()
        } catch {
            hasUnsavedChanges = true
            throw SwitchError.notRecorded(what, cause: error.localizedDescription)
        }
    }

    private func persist(orRestore snapshot: Snapshot) throws {
        do {
            try save()
        } catch {
            (accounts, activeID) = snapshot
            throw error
        }
    }

    func requireReadableIndex() throws {
        if let reason = indexUnusable { throw reason }
    }

    func capture(into id: String) throws {
        try requireReadableIndex()
        let configuration = try CLIState.configurationNow()
        guard accounts.contains(where: { $0.id == id }) else {
            throw SwitchError.unknownAccount(id)
        }
        guard let live = try Keychain.read(service: configuration.credentialService,
                                           account: osAccount) else {
            throw SwitchError.nothingToCapture
        }
        guard let liveEmail = liveEmail() else {
            throw SwitchError.identityUnknown
        }
        try capture(into: id, observing: liveEmail, credential: live, using: configuration)
    }

    func capture(
        into id: String,
        observing liveEmail: String,
        credential live: Data,
        using configuration: CLIConfiguration
    ) throws {
        guard let account = accounts.first(where: { $0.id == id }) else {
            throw SwitchError.unknownAccount(id)
        }
        guard Account.sameAddress(liveEmail, account.email) else {
            throw SwitchError.identityMismatch(expected: account.email, actual: liveEmail)
        }

        let stateFile = configuration.stateFile()
        _ = try stateFile.require()
        let read = stateFile.url.flatMap { CLIState.readIdentity(at: $0) }
        let identity = read.flatMap { $0.matches(liveEmail) ? $0 : nil }
        Journal.log("capture", [
            "account": account.email,
            "payload": Journal.fingerprint(live),
            "stampSays": liveEmail,
            "identity": identity?.email ?? "none",
            "identityIgnored": String(read != nil && identity == nil),
            "stateFile": stateFile.journalName,
        ])
        _ = try writeVerified(live, to: Slot.parked(id), label: account.display)
        noteStored(id, payload: CredentialPayload(raw: live), identity: identity)
        noteTheLiveLoginWasClaimed(id)
        activeID = id
        try recordCompletedChange("storing \(account.display)'s login")
        askWhoseTokenIsInTheSlot(
            expecting: account.email,
            credential: live,
            at: "capture"
        )
    }

    func noteActivated(_ id: String, target: Account) throws {
        activeID = id
        if let index = accounts.firstIndex(of: target) {
            accounts[index].lastActivatedAt = Date()
        }
        try recordCompletedChange("the switch to \(target.display)")
    }

    func noteStored(_ id: String, payload: CredentialPayload, identity: CLIIdentity?) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].hasStoredCredentials = true
        accounts[index].refreshExpiresAt = payload.oauth?.refreshExpires
        accounts[index].accessExpiresAt = payload.accessExpires
        if let identity { accounts[index].identity = identity }
        hasUnsavedChanges = true
    }

    func noteTheLiveLoginWasClaimed(_ id: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].authRefusedAt = nil
        hasUnsavedChanges = true
    }

    func noteRenewed(_ renewals: [String: RenewedLogin]) {
        var touched = false
        for (id, login) in renewals {
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { continue }
            guard accounts[index].allowsARenewalFor(login.account) else {
                Journal.log("renew.wrongAccount", [
                    "expected": accounts[index].email,
                    "said": login.account ?? "-",
                    "hat": String(id.prefix(8)),
                ])
                continue
            }
            accounts[index] = accounts[index].afterARenewal(login)
            touched = true
        }
        guard touched else { return }
        hasUnsavedChanges = true
        do {
            try recordCompletedChange("a renewed login")
        } catch {
            Journal.log("renew.notRecorded", ["reason": error.localizedDescription])
        }
    }

    func noteAuthObservation(refused: Set<String>, accepted: Set<String>, at now: Date = Date()) {
        let changes = AuthObservation.changes(in: accounts, refused: refused, accepted: accepted, at: now)
        guard !changes.isEmpty else { return }
        for change in changes {
            guard let index = accounts.firstIndex(where: { $0.id == change.id }) else { continue }
            accounts[index].authRefusedAt = change.refusedAt
            Journal.log(change.journalEvent, ["account": change.display])
        }
        hasUnsavedChanges = true
        do {
            try recordCompletedChange("an authorization observation")
        } catch {
            Journal.log("auth.observationNotRecorded", ["reason": error.localizedDescription])
        }
    }

    @discardableResult
    func reconcileWithLiveLogin(
        observing identity: LiveIdentity,
        claiming claim: CredentialClaim
    ) throws -> ReconcileOutcome {
        try requireReadableIndex()
        let configuration = try CLIState.configurationNow()
        let email: String
        switch identity {
        case .unreadable:
            return .identityUnreadable
        case .loggedOut:
            return .nobodyLoggedIn
        case .account(let live):
            email = live
        }

        let live: Data
        switch LiveSlotReading(liveSlotNow(inSlot: configuration.credentialService)) {
        case .unsettled(let outcome):
            return outcome
        case .credential(let data):
            live = data
        }

        guard let match = accounts.first(
            where: { Account.sameAddress($0.email, email) }) else {
            guard claim.allowsDiscovery(of: email, credential: live) else {
                Journal.log("reconcile.credentialNotClaimed", [
                    "account": email,
                    "known": "no",
                    "live": Journal.fingerprint(live),
                ])
                return .credentialUnclaimed
            }
            let account = try add(email: email, browser: nil)
            try capture(into: account.id, observing: email, credential: live, using: configuration)
            return .reconciled(account: email, changed: true)
        }

        if match.hasStoredCredentials && match.identity != nil {
            let stored = try Keychain.read(service: Slot.parked(match.id), account: osAccount)
            if stored != live, claim.allows(account: match.email, credential: live) {
                try capture(into: match.id, observing: email, credential: live, using: configuration)
                return .reconciled(account: email, changed: true)
            }
            if stored != live {
                Journal.log("reconcile.credentialNotClaimed", [
                    "account": match.email,
                    "live": Journal.fingerprint(live),
                    "stored": Journal.fingerprint(stored),
                ])
                guard claim.allowsAnUnclaimedMismatch else { return .credentialUnclaimed }
            }
            let changed = activeID != match.id
            activeID = match.id
            if changed || hasUnsavedChanges {
                try recordCompletedChange("the account list")
            }
            return .reconciled(account: email, changed: changed)
        }
        guard claim.allowsDiscovery(of: match.email, credential: live) else {
            Journal.log("reconcile.credentialNotClaimed", [
                "account": match.email,
                "known": "yes, without stored credentials",
                "live": Journal.fingerprint(live),
            ])
            return .credentialUnclaimed
        }
        try capture(into: match.id, observing: email, credential: live, using: configuration)
        return .reconciled(account: email, changed: true)
    }

    @discardableResult
    func pruneOrphanedCredentials() -> Int {
        guard indexUnusable == nil else { return 0 }
        let parked: [String]
        do {
            parked = try Keychain.parkedAccountIDs(account: osAccount)
        } catch {
            Journal.log("prune.skipped", ["reason": error.localizedDescription])
            return 0
        }
        let known = Set(accounts.map(\.id))
        var removed = 0
        for id in parked where !known.contains(id) {
            let payload = try? Keychain.read(service: Slot.parked(id), account: osAccount)
            if (try? Keychain.deleteParked(id: id, account: osAccount)) != nil {
                Journal.log("prune.orphan", [
                    "id": String(id.prefix(8)),
                    "payload": Journal.fingerprint(payload ?? nil),
                ])
                removed += 1
            }
        }
        return removed
    }

    func add(email: String, browser: BrowserChoice?) throws -> Account {
        try requireReadableIndex()
        guard let address = Account.storableAddress(email) else {
            throw SwitchError.blankAddress
        }
        let before = snapshot
        if let existing = accounts.first(
            where: { Account.sameAddress($0.email, address) }) {
            throw SwitchError.duplicateEmail(existing.display)
        }
        let account = Account(id: UUID().uuidString, email: address, browser: browser)
        accounts.append(account)
        try persist(orRestore: before)
        return account
    }

    func beginLogin(_ id: String) throws -> SignInCommand {
        try requireReadableIndex()
        let before = snapshot
        guard let account = accounts.first(where: { $0.id == id }) else {
            throw SwitchError.unknownAccount(id)
        }
        guard let browser = account.browser, browser.overridesBrowser else {
            throw SwitchError.noBrowser(account.display)
        }
        let command = try SignInCommand.of(email: account.email, browser: account.browser)
        if let index = accounts.firstIndex(of: account) {
            accounts[index].lastLoginAt = Date()
            try persist(orRestore: before)
        }

        return command
    }

    func remove(_ id: String) throws {
        try requireReadableIndex()
        let before = snapshot
        guard id != activeID else { throw SwitchError.cannotRemoveActive }
        guard accounts.count > 1 else { throw SwitchError.cannotRemoveLast }
        let payload = try? Keychain.read(service: Slot.parked(id), account: osAccount)
        let display = accounts.first(where: { $0.id == id })?.display ?? id
        accounts.removeAll { $0.id == id }
        try persist(orRestore: before)
        var deletionError: Error?
        do {
            try Keychain.deleteParked(id: id, account: osAccount)
        } catch {
            deletionError = error
        }
        Journal.log("remove", [
            "id": String(id.prefix(8)),
            "payload": Journal.fingerprint(payload ?? nil),
            "credentialDeleted": deletionError == nil ? "true" : "failed",
            "deletionFailure": deletionError?.localizedDescription ?? "none",
        ])
        if let deletionError {
            throw SwitchError.credentialNotDeleted(
                display, cause: deletionError.localizedDescription)
        }
    }

    func update(_ account: Account) throws {
        try requireReadableIndex()
        let before = snapshot
        guard let index = accounts.firstIndex(of: account) else { return }
        accounts[index] = account
        try persist(orRestore: before)
    }

    private(set) var indexUnusable: SwitchError?

    private func load() {
        switch file.load() {
        case .contents(let contents):
            accounts = contents.accounts
            activeID = contents.activeID
            Keychain.adoptLegacyParked(ids: accounts.map(\.id), account: osAccount)
        case .nothingYet:
            break
        case .unusable(let reason):
            indexUnusable = reason
        }
    }

    private func save() throws {
        if let reason = indexUnusable { throw reason }
        try file.save(AccountsFile.Contents(accounts: accounts, activeID: activeID))
        hasUnsavedChanges = false
    }
}
