import Foundation

extension AutoSwitchWatch {
    enum RenewalStep: Equatable {
        case minted(RenewedLogin)
        case trouble(UsageTrouble)
    }

    enum LiveSlotStanding: Equatable {
        case doesNotCarryIt
        case carriesIt
        case cannotBeRead
    }

    static func recordAfterARenewal(
        _ renewal: (refreshToken: String, scopes: [String]),
        in service: String,
        for id: String,
        in batch: inout Batch,
        world: UsageWorld
    ) {
        switch Self.renewed(renewal.refreshToken, scopes: renewal.scopes, in: service, world: world) {
        case .minted(let login):
            batch.renewals[id] = login
            Self.record(world.usage(login.accessToken), for: id, in: &batch, isWearing: false)
        case .trouble(let trouble):
            batch.troubles[id] = trouble
        }
    }

    static func renewed(_ refreshToken: String,
                        scopes: [String],
                        in service: String,
                        world: UsageWorld) -> RenewalStep {
        if let refusal = Self.refusalBeforeSpending(refreshToken, in: service, world: world) {
            return .trouble(refusal)
        }
        switch world.renew(refreshToken, scopes) {
        case .needsLogin:
            world.log("renew.refused", ["slot": service])
            return .trouble(.parkedNeedsLogin)
        case .failed(let reason):
            world.log("renew.failed", ["reason": reason, "slot": service])
            return .trouble(.renewalFailed(reason))
        case .renewed(let login):
            return Self.stored(login, sentWith: refreshToken, in: service, world: world)
        }
    }

    private static func refusalBeforeSpending(_ refreshToken: String,
                                              in service: String,
                                              world: UsageWorld) -> UsageTrouble? {
        switch Self.standingOfTheLiveSlot(refreshToken, world: world) {
        case .carriesIt:
            world.log("renew.notAttempted", ["reason": "the hat is worn", "slot": service])
            return .renewalFailed("the hat is worn, so the CLI renews this login itself")
        case .cannotBeRead:
            world.log("renew.notAttempted", ["reason": "the worn login could not be read", "slot": service])
            return .renewalFailed("the worn login could not be checked")
        case .doesNotCarryIt:
            return nil
        }
    }

    static func standingOfTheLiveSlot(_ refreshToken: String, world: UsageWorld) -> LiveSlotStanding {
        guard let liveSlot = world.liveSlot() else { return .doesNotCarryIt }
        let live: Data?
        do {
            live = try world.read(liveSlot)
        } catch {
            return .cannotBeRead
        }
        guard let live else { return .doesNotCarryIt }

        return CredentialRewrite.matches(refreshToken, in: live) ? .carriesIt : .doesNotCarryIt
    }
}
