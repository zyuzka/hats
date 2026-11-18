import Foundation

enum CodexAuthProblem: Equatable {
    case notJSON
    case notChatGPT
    case noTokens
    case noOwner
}

struct CodexAuth {
    let root: [String: Any]

    static let chatgpt = "chatgpt"

    init(root: [String: Any]) { self.root = root }

    init?(data: Data) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        self.root = root
    }

    var authMode: String? { root["auth_mode"] as? String }
    var tokens: [String: Any] { root["tokens"] as? [String: Any] ?? [:] }
    var idToken: String? { token("id_token") }
    var accessToken: String? { token("access_token") }
    var refreshToken: String? { token("refresh_token") }
    var identity: CodexIdentity? { idToken.flatMap(CodexIdentity.of(idToken:)) }
    var owner: CodexOwner? { identity?.owner }
    var accessExpiry: Date? { accessToken.flatMap(CodexJWT.expiry) }
    var lastRefresh: Date? { (root["last_refresh"] as? String).flatMap(Self.date) }

    func token(_ name: String) -> String? {
        guard let value = tokens[name] as? String, !value.isEmpty else { return nil }
        return value
    }

    var problem: CodexAuthProblem? {
        guard authMode == Self.chatgpt else { return .notChatGPT }
        guard idToken != nil, accessToken != nil, refreshToken != nil else { return .noTokens }
        guard identity != nil else { return .noOwner }

        return nil
    }

    static func problem(of data: Data) -> CodexAuthProblem? {
        guard let auth = CodexAuth(data: data) else { return .notJSON }
        return auth.problem
    }

    func data() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    static func signedIn(
        idToken: String,
        accessToken: String,
        refreshToken: String,
        loginOwnerID: String,
        at now: Date
    ) -> CodexAuth {
        let account = CodexIdentity.of(idToken: idToken)?.owner.accountID
        let tokens: [String: Any] = [
            "id_token": idToken,
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "oauth_provenance": ["issuer": CodexOAuth.issuer, "client_id": CodexOAuth.clientID],
            "login_owner_id": loginOwnerID,
            "account_id": account.map { $0 as Any } ?? NSNull(),
        ]

        return CodexAuth(root: [
            "auth_mode": chatgpt,
            "OPENAI_API_KEY": NSNull(),
            "tokens": tokens,
            "last_refresh": stamp(now),
        ])
    }

    func renewed(idToken: String?, accessToken: String?, refreshToken: String?, at now: Date) -> CodexAuth {
        var tokens = self.tokens
        if let idToken { tokens["id_token"] = idToken }
        if let accessToken { tokens["access_token"] = accessToken }
        if let refreshToken { tokens["refresh_token"] = refreshToken }
        var root = self.root
        root["tokens"] = tokens
        root["last_refresh"] = Self.stamp(now)

        return CodexAuth(root: root)
    }

    static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")

        return formatter.string(from: date)
    }

    static func date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let whole = text.replacingOccurrences(of: #"\.[0-9]+"#, with: "", options: .regularExpression)

        return ISO8601DateFormatter().date(from: whole)
    }
}
