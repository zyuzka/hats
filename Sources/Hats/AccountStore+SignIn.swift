import Foundation

extension AccountStore {
    func parkTheLiveLoginBeforeSigningIn(_ target: Account) throws {
        let configuration = try CLIState.configurationNow(world: system)
        let askedSlot = CLIState.credentialService(environment: CLIState.configuration(from: system.ownEnvironment()))
        guard configuration.credentialService == askedSlot else {
            Journal.log("signIn.liveNotParked", ["reason": "sessions use another configuration"])
            return
        }
        let live: Data
        switch liveSlotNow(inSlot: configuration.credentialService) {
        case .empty:
            return
        case .unreadable:
            Journal.log("signIn.liveNotParked", ["reason": "live slot unreadable"])
            return
        case .holding(let data):
            live = data
        }
        let email: String
        switch liveIdentity() {
        case .loggedOut:
            return
        case .unreadable:
            Journal.log("signIn.liveNotParked", [
                "reason": "owner unknown",
                "live": Journal.fingerprint(live),
            ])
            return
        case .account(let owner):
            email = owner
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
