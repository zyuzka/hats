import Foundation

struct CodexOwner: Codable, Equatable, Hashable {
    let userID: String
    let accountID: String
}

struct CodexIdentity: Equatable {
    let owner: CodexOwner
    let email: String?
    let plan: String?

    static let authClaim = "https://api.openai.com/auth"
    static let profileClaim = "https://api.openai.com/profile"

    static func of(idToken: String) -> CodexIdentity? {
        guard let payload = CodexJWT.payload(idToken) else { return nil }
        let auth = payload[authClaim] as? [String: Any] ?? [:]
        let user = text(auth["chatgpt_user_id"]) ?? text(auth["user_id"]) ?? text(payload["sub"])
        guard let user, let account = text(auth["chatgpt_account_id"]) else { return nil }
        let profile = payload[profileClaim] as? [String: Any] ?? [:]

        return CodexIdentity(
            owner: CodexOwner(userID: user, accountID: account),
            email: text(payload["email"]) ?? text(profile["email"]),
            plan: text(auth["chatgpt_plan_type"])
        )
    }

    static func text(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        return Account.storableAddress(raw)
    }
}

enum CodexJWT {
    static func payload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        guard let data = base64URLDecoded(String(parts[1])) else { return nil }

        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func expiry(_ jwt: String) -> Date? {
        guard let number = payload(jwt)?["exp"] as? NSNumber, !TokenRenewal.isBoolean(number) else {
            return nil
        }
        let seconds = number.doubleValue
        guard seconds.isFinite, seconds > 0 else { return nil }

        return Date(timeIntervalSince1970: seconds)
    }

    static func base64URLDecoded(_ text: String) -> Data? {
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)

        return Data(base64Encoded: standard)
    }

    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
