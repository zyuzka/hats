import Foundation

struct RenewedLogin: Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let refreshExpiresAt: Date?
    let scopes: [String]
    let account: String?
}

enum Renewal: Equatable {
    case renewed(RenewedLogin)
    case needsLogin
    case failed(String)
}

enum TokenRenewal {
    static let endpoint = URL(string: "https://platform.claude.com/v1/oauth/token")
        ?? URL(fileURLWithPath: "/")
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let scopesTheCLIAsksFor = [
        "user:profile",
        "user:inference",
        "user:sessions:claude_code",
        "user:mcp_servers",
        "user:file_upload",
    ]
    static let budget: TimeInterval = 30
    static let refusedGrant = "invalid_grant"

    static func body(refreshToken: String, scopes: [String]) -> Data? {
        let asked = scopes.isEmpty ? scopesTheCLIAsksFor : scopes
        return try? JSONSerialization.data(
            withJSONObject: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID,
                "scope": asked.joined(separator: " "),
            ],
            options: [.sortedKeys]
        )
    }

    static func request(refreshToken: String,
                        scopes: [String],
                        endpoint: URL = endpoint) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = budget
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body(refreshToken: refreshToken, scopes: scopes)

        return request
    }

    static func outcome(status: Int,
                        body: Data?,
                        keeping refreshToken: String,
                        at now: Date = Date()) -> Renewal {
        guard status != 0 else { return .failed("unreachable") }
        guard status == 200 else {
            return isGrantRefused(status: status, body: body)
                ? .needsLogin
                : .failed("http \(status)")
        }
        guard let body,
              let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        else { return .failed("the renewal answer could not be read") }
        guard let token = payload["access_token"] as? String, !token.isEmpty
        else { return .failed("the renewed login carries no token") }
        guard let lifetime = Self.seconds(payload["expires_in"])
        else { return .failed("the renewed login carries no expiry") }
        return .renewed(RenewedLogin(
            accessToken: token,
            refreshToken: (payload["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? refreshToken,
            expiresAt: now.addingTimeInterval(lifetime),
            refreshExpiresAt: Self.seconds(payload["refresh_token_expires_in"])
                .map { now.addingTimeInterval($0) },
            scopes: Self.scopes(payload["scope"]),
            account: (payload["account"] as? [String: Any])?["email_address"] as? String
        ))
    }

    static func isGrantRefused(status: Int, body: Data?) -> Bool {
        guard status == 400 || status == 401 else { return false }
        guard let body,
              let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        else { return false }
        return Self.errorCode(payload) == refusedGrant
    }

    static func errorCode(_ payload: [String: Any]) -> String? {
        if let code = payload["error"] as? String { return code }
        return (payload["error"] as? [String: Any])?["type"] as? String
    }

    static func scopes(_ value: Any?) -> [String] {
        guard let text = value as? String else { return [] }
        return text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    static func isBoolean(_ value: NSNumber) -> Bool {
        CFGetTypeID(value) == CFBooleanGetTypeID()
    }

    static func seconds(_ value: Any?) -> TimeInterval? {
        guard let number = value as? NSNumber, !Self.isBoolean(number) else { return nil }
        let lifetime = number.doubleValue
        guard lifetime.isFinite, lifetime > 0 else { return nil }

        return lifetime
    }

    static func renew(refreshToken: String,
                      scopes: [String],
                      endpoint: URL = endpoint,
                      at now: Date = Date()) -> Renewal {
        OneShotRequest.answer(
            to: request(refreshToken: refreshToken, scopes: scopes, endpoint: endpoint),
            within: budget,
            unreachable: .failed("unreachable"),
            reading: { status, body in
                outcome(status: status, body: body, keeping: refreshToken, at: now)
            }
        )
    }
}
