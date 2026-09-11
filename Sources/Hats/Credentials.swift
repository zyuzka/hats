import Foundation

struct OAuthBlock: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Double?
    var refreshTokenExpiresAt: Double?
    var scopes: [String]?
    var subscriptionType: String?
    var rateLimitTier: String?

    var expires: Date? { expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var refreshExpires: Date? { refreshTokenExpiresAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

struct CredentialPayload {
    let raw: Data
    let oauth: OAuthBlock?
    let mcpKeys: [String]

    init(raw: Data) {
        self.raw = raw
        let object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]

        if let block = object?["claudeAiOauth"],
           let blockData = try? JSONSerialization.data(withJSONObject: block) {
            self.oauth = try? JSONDecoder().decode(OAuthBlock.self, from: blockData)
        } else {
            self.oauth = nil
        }

        self.mcpKeys = ((object?["mcpOAuth"] as? [String: Any])?.keys).map(Array.init)?.sorted() ?? []
    }

    var accessExpires: Date? { oauth?.expires }

    var accessToken: String? { oauth?.accessToken }

    var scopes: [String] { oauth?.scopes ?? [] }

    func hasAUsableAccessToken(at now: Date = Date()) -> Bool {
        guard let token = accessToken, !token.isEmpty else { return false }
        guard let expires = accessExpires else { return true }
        return expires > now
    }

    func refreshTokenStillGoodForARenewal(at now: Date = Date()) -> String? {
        guard let token = oauth?.refreshToken, !token.isEmpty else { return nil }
        if let expires = oauth?.refreshExpires, expires <= now { return nil }
        return token
    }
}
