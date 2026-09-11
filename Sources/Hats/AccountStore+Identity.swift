import Foundation

extension AccountStore {
    func askWhoseTokenIsInTheSlot(
        expecting expected: String,
        credential: Data,
        at moment: String
    ) {
        let fetching = fetchingTokenIdentity
        identityQueue.async {
            let verdict = IdentityCheck.of(
                expected,
                credential: CredentialPayload(raw: credential),
                fetching: fetching
            )
            let details = verdict.journalled(at: moment, expecting: expected)
            DispatchQueue.main.async {
                Journal.log(IdentityCheck.operation, details)
            }
        }
    }

    enum OutgoingLogin {
        case nobody
        case theTarget
        case another(String)
    }

    func outgoingLogin(_ live: Data?, target: Account) throws -> OutgoingLogin {
        guard live != nil else { return .nobody }
        guard let email = liveEmail() else {
            throw SwitchError.identityUnknown
        }
        return Account.sameAddress(email, target.email) ? .theTarget : .another(email)
    }
}
