import Foundation

extension AccountStore {
    func parkTheLiveLoginBeforeSigningIn(_ target: Account) throws {
        let configuration = try CLIState.configurationNow(world: system)
        guard let live = try keychain.read(configuration.credentialService) else { return }
        guard let email = liveEmail() else {
            Journal.log("signIn.liveNotParked", [
                "reason": "owner unknown",
                "live": Journal.fingerprint(live),
            ])
            return
        }
        guard !Account.sameAddress(email, target.email) else { return }
        guard accounts.contains(where: { Account.sameAddress($0.email, email) }) else {
            Journal.log("signIn.liveNotParked", [
                "reason": "not a hat",
                "live": Journal.fingerprint(live),
            ])
            return
        }

        try park(live, belongingTo: email, statedIn: configuration.stateFile())
    }
}
