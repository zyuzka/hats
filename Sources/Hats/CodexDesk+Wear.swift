import Foundation

enum CodexAutoWear: Equatable {
    case worn(CodexWorn, [CodexRenewed])
    case moved
    case failed(String)
}

extension CodexDesk {
    func wear(
        _ target: CodexTicket,
        among hats: [CodexTicket],
        then: @escaping (Result<CodexWorn, Error>, [CodexRenewed]) -> Void
    ) {
        world.run { [self] in
            switch wearAndRenewTheParked(target, among: hats) {
            case .success(let done): world.onMain { then(.success(done.worn), done.renewed) }
            case .failure(let error): world.onMain { then(.failure(error), []) }
            }
        }
    }

    func wear(
        _ target: CodexTicket,
        insteadOf expected: String,
        among hats: [CodexTicket],
        then: @escaping (CodexAutoWear) -> Void
    ) {
        world.run { [self] in
            guard isStillWorn(expected, among: hats) else { return world.onMain { then(.moved) } }
            switch wearAndRenewTheParked(target, among: hats) {
            case .success(let done): world.onMain { then(.worn(done.worn, done.renewed)) }
            case .failure(let error): world.onMain { then(.failed(error.localizedDescription)) }
            }
        }
    }

    private func wearAndRenewTheParked(
        _ target: CodexTicket,
        among hats: [CodexTicket]
    ) -> Result<(worn: CodexWorn, renewed: [CodexRenewed]), Error> {
        do {
            let worn = try wearNow(target, among: hats)
            var renewed: [CodexRenewed] = []
            if case .worn(_, let outgoing?, _) = worn, let hat = hats.first(where: { $0.id == outgoing }) {
                renewed = renewOne(hat, forced: true).map { [$0] } ?? []
            }
            return .success((worn, renewed))
        } catch {
            Journal.log("codex.wear.refused", [
                "target": String(target.id.prefix(8)),
                "reason": error.localizedDescription,
            ])
            return .failure(error)
        }
    }

    func relogin(
        _ target: CodexTicket,
        with data: Data,
        isWorn: Bool,
        among hats: [CodexTicket],
        then: @escaping (_ stored: Bool, Result<CodexWorn?, Error>) -> Void
    ) {
        world.run { [self] in
            do {
                try world.keychain.writeVerified(data, to: Slot.codexParked(target.id), label: target.title)
            } catch {
                Journal.log("codex.relogin.notStored", [
                    "target": String(target.id.prefix(8)),
                    "reason": error.localizedDescription,
                ])
                return world.onMain { then(false, .failure(error)) }
            }
            forget(target.id)
            Journal.log("codex.relogin.stored", ["target": String(target.id.prefix(8)), "worn": String(isWorn)])
            do {
                let worn = isWorn ? try replaceLive(with: data, for: target, among: hats) : nil
                world.onMain { then(true, .success(worn)) }
            } catch {
                Journal.log("codex.relogin.liveNotReplaced", [
                    "target": String(target.id.prefix(8)),
                    "reason": error.localizedDescription,
                ])
                world.onMain { then(true, .failure(error)) }
            }
        }
    }

    func wearNow(_ target: CodexTicket, among hats: [CodexTicket]) throws -> CodexWorn {
        let incoming = try heldOrStored(target)
        guard CodexAuth(data: incoming)?.owner == target.owner else {
            throw CodexError.notTheSameOwner(target.title)
        }
        var outgoing: CodexTicket?
        var parked: Data?
        var kept: Data?
        let written = try world.home.swap(in: incoming) { live in
            guard let live else { return .write }
            let owner = try ownerOf(live)
            if owner == target.owner {
                kept = live
                return .keep
            }
            guard let hat = hats.first(where: { $0.owner == owner }) else {
                throw CodexError.foreignLogin(CodexAuth(data: live)?.identity?.email ?? owner.accountID)
            }
            try world.keychain.writeVerified(live, to: Slot.codexParked(hat.id), label: hat.title)
            Journal.log("codex.park.outgoing", ["hat": String(hat.id.prefix(8)), "payload": Journal.fingerprint(live)])
            forget(hat.id)
            outgoing = hat
            parked = live
            return .write
        }
        noteWornHere(target.id)
        onLiveWritten?(target.id, written ? incoming : kept ?? incoming)
        guard written else { return .alreadyWorn(target.id) }
        forget(target.id)
        Journal.log("codex.wear.done", ["target": String(target.id.prefix(8)), "now": Journal.fingerprint(incoming)])

        return .worn(target: target.id, outgoing: outgoing?.id, parked: parked)
    }

    func replaceLive(with data: Data, for target: CodexTicket, among hats: [CodexTicket]) throws -> CodexWorn {
        var outgoing: CodexTicket?
        var parked: Data?
        try world.home.swap(in: data) { live in
            guard let live else { return .write }
            let owner = try ownerOf(live)
            if owner == target.owner { return .write }
            guard let hat = hats.first(where: { $0.owner == owner }) else {
                throw CodexError.foreignLogin(owner.accountID)
            }
            try world.keychain.writeVerified(live, to: Slot.codexParked(hat.id), label: hat.title)
            outgoing = hat
            parked = live
            return .write
        }
        noteWornHere(target.id)
        onLiveWritten?(target.id, data)

        return .worn(target: target.id, outgoing: outgoing?.id, parked: parked)
    }

    private func ownerOf(_ live: Data) throws -> CodexOwner {
        guard let owner = CodexAuth(data: live)?.owner else { throw CodexError.liveUnusable("it names no owner") }
        return owner
    }
}
