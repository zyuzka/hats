import Foundation

enum CredentialRewrite {
    static let oauthKey = "claudeAiOauth"

    static func millisecondsSinceEpoch(_ date: Date) -> Int? {
        Int(exactly: (date.timeIntervalSince1970 * 1000).rounded())
    }

    static func matches(_ refreshToken: String, in raw: Data) -> Bool {
        guard let stored = CredentialPayload(raw: raw).oauth?.refreshToken, !stored.isEmpty else {
            return false
        }
        return stored == refreshToken
    }

    static func merged(_ raw: Data, with renewed: RenewedLogin) -> Data? {
        guard var object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
        else { return nil }
        guard let expiresAt = millisecondsSinceEpoch(renewed.expiresAt) else { return nil }
        var oauth = object[oauthKey] as? [String: Any] ?? [:]
        oauth["accessToken"] = renewed.accessToken
        oauth["refreshToken"] = renewed.refreshToken
        oauth["expiresAt"] = expiresAt
        if let refreshExpiresAt = renewed.refreshExpiresAt {
            guard let stamp = millisecondsSinceEpoch(refreshExpiresAt) else { return nil }
            oauth["refreshTokenExpiresAt"] = stamp
        }
        if !renewed.scopes.isEmpty { oauth["scopes"] = renewed.scopes }
        object[oauthKey] = oauth

        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
