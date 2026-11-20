import Foundation

enum CodexWornRenewal: Equatable {
    case fresh(Data)
    case notDue(Data)
    case elsewhere
    case needsSignIn(String)
    case failed(String)
}

extension CodexDesk {
    static let codexWriteStep: TimeInterval = 0.5

    func renewWornNow(_ hat: CodexTicket, refused: String? = nil) -> CodexWornRenewal {
        let live: Data
        do {
            guard let read = try world.home.readLiveChecked() else { return .elsewhere }
            live = read
        } catch {
            return .failed(error.localizedDescription)
        }
        guard let auth = CodexAuth(data: live), auth.owner == hat.owner else { return .elsewhere }
        if let refused, auth.accessToken != refused { return .fresh(live) }
        if let pending = held[hat.id] { return writeWorn(pending, for: hat, replacing: auth) }
        let now = world.now()
        if refused == nil, !CodexRenewal.isDue(auth, at: now) { return .notDue(live) }
        guard let refresh = auth.refreshToken else { return .needsSignIn("the live login has no refresh token") }
        guard refused != nil || backoff.allows(hat.id, at: now) else { return .notDue(live) }
        let reply = world.send(CodexRenewal.request(refreshToken: refresh))

        return settleWorn(CodexRenewal.answer(status: reply.status, body: reply.body), for: hat, sent: auth, at: now)
    }

    private func settleWorn(_ answer: CodexRenewal.Answer, for hat: CodexTicket, sent auth: CodexAuth, at now: Date)
        -> CodexWornRenewal {
        switch answer {
        case .renewed(let fields):
            switch CodexRenewal.merge(fields, into: auth, owner: hat.owner, at: world.now(), encode: encode) {
            case .wrongOwner:
                Journal.log("codex.wornRenew.wrongOwner", ["hat": String(hat.id.prefix(8))])
                return .needsSignIn("the renewed login names another account")
            case .unwritable:
                Journal.log("codex.wornRenew.notEncoded", ["hat": String(hat.id.prefix(8))])
                return .failed("the renewed login could not be encoded")
            case .merged(let data):
                held[hat.id] = data
                mark(hat.id, unsaved: true)
                return writeWorn(data, for: hat, replacing: auth)
            }
        case .needsSignIn(let why):
            Journal.log("codex.wornRenew.refused", ["hat": String(hat.id.prefix(8)), "reason": why])
            return codexWrites(after: auth, for: hat).map(CodexWornRenewal.fresh) ?? .needsSignIn(why)
        case .failed(let why):
            Journal.log("codex.wornRenew.failed", ["hat": String(hat.id.prefix(8)), "reason": why])
            backoff.failed(hat.id, at: now, pollingEvery: interval)
            return .failed(why)
        }
    }

    func writeWorn(_ data: Data, for hat: CodexTicket, replacing old: CodexAuth) -> CodexWornRenewal {
        var outcome = CodexWornRenewal.fresh(data)
        do {
            let written = try world.home.swap(in: data) { current in
                guard let current, let now = CodexAuth(data: current), now.owner == hat.owner else {
                    try world.keychain.writeVerified(data, to: Slot.codexParked(hat.id), label: hat.title)
                    Journal.log("codex.wornRenew.parkedElsewhere", ["hat": String(hat.id.prefix(8))])
                    outcome = .elsewhere
                    return .keep
                }
                guard now.accessToken == old.accessToken, now.refreshToken == old.refreshToken else {
                    Journal.log("codex.wornRenew.codexWasFirst", ["hat": String(hat.id.prefix(8))])
                    outcome = .fresh(current)
                    return .keep
                }
                return .write
            }
            if written { saveToTheSlot(data, for: hat) }
        } catch {
            Journal.log("codex.wornRenew.notWritten", [
                "hat": String(hat.id.prefix(8)),
                "reason": error.localizedDescription,
            ])
            return .failed(error.localizedDescription)
        }
        held.removeValue(forKey: hat.id)
        mark(hat.id, unsaved: false)
        backoff.succeeded(hat.id)

        return outcome
    }

    private func saveToTheSlot(_ data: Data, for hat: CodexTicket) {
        do {
            try world.keychain.writeVerified(data, to: Slot.codexParked(hat.id), label: hat.title)
            Journal.log("codex.wornRenew.saved", [
                "hat": String(hat.id.prefix(8)),
                "payload": Journal.fingerprint(data),
            ])
        } catch {
            Journal.log("codex.wornRenew.slotNotSaved", [
                "hat": String(hat.id.prefix(8)),
                "reason": error.localizedDescription,
            ])
        }
    }

    func codexWrites(after sent: CodexAuth, for hat: CodexTicket) -> Data? {
        let steps = max(1, Int((world.waitForCodex / Self.codexWriteStep).rounded(.up)))
        for step in 0...steps {
            if let live = try? world.home.readLiveChecked(), let auth = CodexAuth(data: live), auth.owner == hat.owner,
               auth.accessToken != sent.accessToken || auth.refreshToken != sent.refreshToken {
                Journal.log("codex.wornRenew.tookCodexWrite", ["hat": String(hat.id.prefix(8))])
                return live
            }
            if step < steps { world.pause(Self.codexWriteStep) }
        }

        return nil
    }
}
