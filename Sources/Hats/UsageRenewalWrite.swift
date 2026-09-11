import Foundation

extension AutoSwitchWatch {
    private static func refusalBeforeWriting(_ refreshToken: String,
                                             in service: String,
                                             current: Data,
                                             world: UsageWorld) -> UsageTrouble? {
        guard CredentialRewrite.matches(refreshToken, in: current) else {
            world.log("renew.discarded", ["reason": "the slot moved while it was renewed", "slot": service])
            return .renewalFailed("the login moved while it was being renewed")
        }
        switch Self.standingOfTheLiveSlot(refreshToken, world: world) {
        case .carriesIt:
            world.log("renew.discarded", ["reason": "the hat was worn while it was renewed", "slot": service])
            return .renewalFailed("the hat was worn while its login was being renewed")
        case .cannotBeRead:
            world.log("renew.discarded", ["reason": "the worn login could not be read", "slot": service])
            return .renewalFailed("the worn login could not be checked")
        case .doesNotCarryIt:
            return nil
        }
    }

    static func stored(_ login: RenewedLogin,
                       sentWith refreshToken: String,
                       in service: String,
                       world: UsageWorld) -> RenewalStep {
        let current: Data?
        do {
            current = try world.read(service)
        } catch {
            world.log("renew.notStored", ["reason": "the slot could not be read back", "slot": service])
            return .trouble(.renewalFailed("the slot could not be read back"))
        }
        guard let current else {
            world.log("renew.discarded", ["reason": "the slot moved while it was renewed", "slot": service])
            return .trouble(.renewalFailed("the login moved while it was being renewed"))
        }
        if let refusal = Self.refusalBeforeWriting(refreshToken,
                                                   in: service,
                                                   current: current,
                                                   world: world) {
            return .trouble(refusal)
        }
        guard let merged = CredentialRewrite.merged(current, with: login) else {
            world.log("renew.notStored", ["reason": "the credential could not be rewritten", "slot": service])
            return .trouble(.renewalFailed("the credential could not be rewritten"))
        }

        return Self.written(merged, for: login, in: service, world: world)
    }

    private static func written(_ merged: Data,
                                for login: RenewedLogin,
                                in service: String,
                                world: UsageWorld) -> RenewalStep {
        do {
            try world.write(service, merged)
        } catch {
            world.log("renew.notStored", [
                "detail": error.localizedDescription,
                "reason": "the keychain refused the write",
                "slot": service,
            ])
            return .trouble(.renewalFailed("the renewed login could not be stored"))
        }
        let written: Data?
        do {
            written = try world.read(service)
        } catch {
            world.log("renew.notStored", [
                "detail": error.localizedDescription,
                "reason": "the write could not be read back",
                "slot": service,
            ])
            return .trouble(.renewalFailed("the renewed login could not be read back"))
        }
        guard written == merged else {
            world.log("renew.notStored", ["reason": "the write did not take", "slot": service])
            return .trouble(.renewalFailed("the renewed login did not reach the keychain"))
        }
        world.log("renew.done", [
            "account": login.account ?? "-",
            "payload": Journal.fingerprint(merged),
            "slot": service,
        ])

        return .minted(login)
    }
}
