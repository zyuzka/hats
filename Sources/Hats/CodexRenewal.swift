import Foundation

enum CodexRenewal {
    static let dueBefore: TimeInterval = 24 * 3600
    static let staleAfter: TimeInterval = 8 * 24 * 3600
    static let refusals = [
        "refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated", "invalid_grant",
    ]

    struct Fields: Equatable {
        let idToken: String?
        let accessToken: String?
        let refreshToken: String?
    }

    enum Answer: Equatable {
        case renewed(Fields)
        case needsSignIn(String)
        case failed(String)
    }

    static func isDue(_ auth: CodexAuth, at now: Date) -> Bool {
        if let expiry = auth.accessExpiry { return expiry.timeIntervalSince(now) < dueBefore }
        guard let last = auth.lastRefresh else { return true }

        return now.timeIntervalSince(last) > staleAfter
    }

    static func request(refreshToken: String) -> URLRequest {
        var request = URLRequest(url: CodexOAuth.tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = CodexOAuth.budget
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: [
                "grant_type": "refresh_token",
                "client_id": CodexOAuth.clientID,
                "refresh_token": refreshToken,
            ],
            options: [.sortedKeys]
        )

        return request
    }

    static func answer(status: Int, body: Data?) -> Answer {
        guard status != 0 else { return .failed("unreachable") }
        if let refusal = refusal(in: body) { return .needsSignIn(refusal) }
        guard status != 401 else { return .needsSignIn("http 401") }
        guard (200..<300).contains(status) else { return .failed("http \(status)") }
        guard let body, let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return .failed("the answer could not be read")
        }
        let id = text(payload["id_token"])
        let access = text(payload["access_token"])
        let refresh = text(payload["refresh_token"])
        guard id != nil || access != nil || refresh != nil else { return .failed("the answer carried no tokens") }

        return .renewed(Fields(idToken: id, accessToken: access, refreshToken: refresh))
    }

    static func refusal(in body: Data?) -> String? {
        guard let body, let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return nil
        }
        let error = payload["error"]
        let codes = [
            error as? String,
            (error as? [String: Any])?["code"] as? String,
            (error as? [String: Any])?["type"] as? String,
            payload["code"] as? String,
            payload["error_code"] as? String,
        ].compactMap { $0 }

        return codes.first { refusals.contains($0) }
    }

    static func text(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    enum Merge: Equatable {
        case merged(Data)
        case wrongOwner
        case unwritable
    }

    static func merge(
        _ answer: Fields,
        into auth: CodexAuth,
        owner: CodexOwner,
        at now: Date,
        encode: (CodexAuth) throws -> Data = { try $0.data() }
    ) -> Merge {
        if let id = answer.idToken, CodexIdentity.of(idToken: id)?.owner != owner { return .wrongOwner }
        let renewed = auth.renewed(
            idToken: answer.idToken,
            accessToken: answer.accessToken,
            refreshToken: answer.refreshToken,
            at: now
        )
        guard let data = try? encode(renewed) else { return .unwritable }

        return .merged(data)
    }
}
