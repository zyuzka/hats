import Foundation

final class CodexDesk {
    let world: CodexWorld
    var interval: TimeInterval = 300
    var encode: (CodexAuth) throws -> Data = { try $0.data() }

    var held: [String: Data] = [:]
    private var heldFields: [String: CodexRenewal.Fields] = [:]
    var backoff = RenewalBackoff()
    var onLiveWritten: ((String, Data) -> Void)?
    private var worn: String?
    private let unsavedLock = NSLock()
    private var unsaved: Set<String> = []

    init(world: CodexWorld) { self.world = world }

    func noteWorn(_ id: String?) {
        world.run { [self] in worn = id }
    }

    func renew(_ hats: [CodexTicket], forcing: Set<String> = [], then: @escaping ([CodexRenewed]) -> Void) {
        world.run { [self] in
            let results = hats.compactMap { renewOne($0, forced: forcing.contains($0.id)) }
            world.onMain { then(results) }
        }
    }

    func heldOrStored(_ hat: CodexTicket) throws -> Data {
        if let pending = held[hat.id] { return pending }
        guard let stored = try world.keychain.read(Slot.codexParked(hat.id)) else {
            throw CodexError.notStoredYet(hat.title)
        }

        return stored
    }

    func forget(_ id: String) {
        held.removeValue(forKey: id)
        heldFields.removeValue(forKey: id)
        mark(id, unsaved: false)
        backoff.succeeded(id)
    }

    func noteWornHere(_ id: String) { worn = id }

    func isStillWorn(_ id: String, among hats: [CodexTicket]) -> Bool {
        guard worn == id, let owner = hats.first(where: { $0.id == id })?.owner else { return false }

        return (try? world.home.readLive()).flatMap { $0 }.flatMap { CodexAuth(data: $0)?.owner } == owner
    }

    func heldIDs() -> [String] {
        unsavedLock.lock()
        defer { unsavedLock.unlock() }

        return unsaved.sorted()
    }

    func mark(_ id: String, unsaved isUnsaved: Bool) {
        unsavedLock.lock()
        defer { unsavedLock.unlock() }
        if isUnsaved { unsaved.insert(id) } else { unsaved.remove(id) }
    }

    func renewOne(_ hat: CodexTicket, forced: Bool) -> CodexRenewed? {
        guard hat.id != worn, !hat.needsSignIn else { return nil }
        if let pending = held[hat.id] { return save(pending, for: hat) }
        let now = world.now()
        guard let stored = try? world.keychain.read(Slot.codexParked(hat.id)),
              let auth = CodexAuth(data: stored), let refresh = auth.refreshToken else { return nil }
        if let fields = heldFields[hat.id] { return settle(.renewed(fields), for: hat, auth: auth, at: now) }
        guard backoff.allows(hat.id, at: now) else { return nil }
        guard forced || CodexRenewal.isDue(auth, at: now) else { return nil }
        let reply = world.send(CodexRenewal.request(refreshToken: refresh))

        return settle(CodexRenewal.answer(status: reply.status, body: reply.body), for: hat, auth: auth, at: now)
    }

    private func settle(_ answer: CodexRenewal.Answer, for hat: CodexTicket, auth: CodexAuth, at now: Date)
        -> CodexRenewed {
        switch answer {
        case .needsSignIn(let why):
            Journal.log("codex.renew.needsSignIn", ["hat": String(hat.id.prefix(8)), "reason": why])
            backoff.succeeded(hat.id)
            return .needsSignIn(hat.id, why)
        case .failed(let why):
            Journal.log("codex.renew.failed", ["hat": String(hat.id.prefix(8)), "reason": why])
            backoff.failed(hat.id, at: now, pollingEvery: interval)
            return .failed(hat.id, why)
        case .renewed(let fields):
            switch CodexRenewal.merge(fields, into: auth, owner: hat.owner, at: world.now(), encode: encode) {
            case .wrongOwner:
                Journal.log("codex.renew.wrongOwner", ["hat": String(hat.id.prefix(8))])
                heldFields.removeValue(forKey: hat.id)
                backoff.succeeded(hat.id)
                return .needsSignIn(hat.id, "the renewed login names another account")
            case .unwritable:
                Journal.log("codex.renew.notEncoded", ["hat": String(hat.id.prefix(8))])
                heldFields[hat.id] = fields
                mark(hat.id, unsaved: true)
                backoff.failed(hat.id, at: now, pollingEvery: interval)
                return .notSaved(hat.id)
            case .merged(let data):
                heldFields.removeValue(forKey: hat.id)
                held[hat.id] = data
                mark(hat.id, unsaved: true)
                return save(data, for: hat)
            }
        }
    }

    private func save(_ data: Data, for hat: CodexTicket) -> CodexRenewed {
        do {
            try world.keychain.writeVerified(data, to: Slot.codexParked(hat.id), label: hat.title)
        } catch {
            Journal.log("codex.renew.notSaved", [
                "hat": String(hat.id.prefix(8)),
                "reason": error.localizedDescription,
            ])
            return .notSaved(hat.id)
        }
        held.removeValue(forKey: hat.id)
        mark(hat.id, unsaved: false)
        backoff.succeeded(hat.id)
        Journal.log("codex.renew.saved", ["hat": String(hat.id.prefix(8)), "payload": Journal.fingerprint(data)])

        return .renewed(hat.id, data)
    }
}
