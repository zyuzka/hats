import Foundation

struct TokenIdentity: Equatable {
    let email: String
    let accountUUID: String
    let organizationUUID: String?
    let organizationName: String?

    static func parsed(_ payload: [String: Any]) -> TokenIdentity? {
        guard let account = payload["account"] as? [String: Any],
              let rawEmail = account["email"] as? String,
              let email = Account.storableAddress(rawEmail),
              let rawUUID = account["uuid"] as? String,
              let accountUUID = Account.storableAddress(rawUUID)
        else { return nil }
        let organization = payload["organization"] as? [String: Any]
        return TokenIdentity(
            email: email,
            accountUUID: accountUUID,
            organizationUUID: (organization?["uuid"] as? String)
                .flatMap { Account.storableAddress($0) },
            organizationName: (organization?["name"] as? String)
                .flatMap { Account.storableAddress($0) }
        )
    }
}

enum IdentityVerdict: Equatable {
    case confirmed(TokenIdentity)
    case mismatch(expected: String, actual: TokenIdentity)
    case unchecked(String)

    init(expecting expected: String, fetch: ProfileFetch) {
        guard let identity = fetch.identity else {
            self = .unchecked(fetch.trouble ?? "unreadable")
            return
        }
        self = Account.sameAddress(identity.email, expected)
            ? .confirmed(identity)
            : .mismatch(expected: expected, actual: identity)
    }

    var identity: TokenIdentity? {
        switch self {
        case .confirmed(let identity): return identity
        case .mismatch(_, let identity): return identity
        case .unchecked: return nil
        }
    }

    var isMismatch: Bool {
        guard case .mismatch = self else { return false }
        return true
    }

    var reading: String {
        switch self {
        case .confirmed: return "confirmed"
        case .mismatch: return "MISMATCH"
        case .unchecked(let why): return "unchecked:\(why)"
        }
    }

    func journalled(at moment: String, expecting expected: String) -> [String: String] {
        [
            "at": moment,
            "expected": expected,
            "tokenSays": identity?.email ?? "-",
            "tokenAccount": identity?.accountUUID ?? "-",
            "tokenOrg": identity?.organizationName ?? "-",
            "verdict": reading,
        ]
    }
}

enum IdentityCheck {
    static let operation = "identity.fromToken"

    static func of(
        _ expected: String,
        credential: CredentialPayload,
        fetching: (String) -> ProfileFetch = { ProfileFetcher.fetch(token: $0) }
    ) -> IdentityVerdict {
        guard credential.hasAUsableAccessToken(), let token = credential.accessToken else {
            return .unchecked("no usable token")
        }
        return IdentityVerdict(expecting: expected, fetch: fetching(token))
    }
}
