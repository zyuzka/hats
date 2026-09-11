import Foundation

extension AutoSwitchWatch {
    enum PollStep: Equatable {
        case fetch(String)
        case renew(String, [String])
        case trouble(UsageTrouble)
    }

    static func step(for payload: CredentialPayload, isWearing: Bool, at now: Date) -> PollStep {
        if payload.hasAUsableAccessToken(at: now), let token = payload.accessToken {
            return .fetch(token)
        }
        let hasAToken = !(payload.accessToken ?? "").isEmpty
        guard !isWearing else { return .trouble(hasAToken ? .tokenExpired : .noTokenStored) }
        guard let refreshToken = payload.refreshTokenStillGoodForARenewal(at: now) else {
            return .trouble(hasAToken ? .parkedNeedsLogin : .noTokenStored)
        }

        return .renew(refreshToken, payload.scopes)
    }

    static func fetched(_ hats: Hats, world: UsageWorld) -> Batch {
        var batch = Batch()
        for hat in hats.filter(\.isWearing) + hats.filter({ !$0.isWearing }) {
            guard let service = hat.isWearing ? world.liveSlot() : Slot.parked(hat.id) else {
                batch.troubles[hat.id] = .liveSlotUnknown
                continue
            }
            let stored: Data?
            do {
                stored = try world.read(service)
            } catch {
                batch.troubles[hat.id] = .credentialUnreadable
                continue
            }
            guard let raw = stored else {
                batch.troubles[hat.id] = .nothingStored
                continue
            }
            let payload = CredentialPayload(raw: raw)
            switch Self.step(for: payload, isWearing: hat.isWearing, at: world.now()) {
            case .trouble(let trouble):
                batch.troubles[hat.id] = trouble
            case .fetch(let token):
                Self.record(
                    world.usage(token),
                    for: hat.id,
                    in: &batch,
                    isWearing: hat.isWearing
                )
            case .renew(let refreshToken, let scopes):
                guard world.mayRenew(hat.id) else { continue }
                Self.recordAfterARenewal(
                    (refreshToken, scopes),
                    in: service,
                    for: hat.id,
                    in: &batch,
                    world: world
                )
            }
        }

        return batch
    }

    static func record(
        _ outcome: UsageFetch,
        for id: String,
        in batch: inout Batch,
        isWearing: Bool = true
    ) {
        batch.record(outcome, for: id, isWearing: isWearing)
    }
}
