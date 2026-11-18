import Foundation

enum CodexHeldAnswer {
    static let maxBytes = 64 * 1024
    static let maxWait: TimeInterval = 10
    static let usageLimit = "usage_limit_reached"

    static func isHeld(_ status: Int) -> Bool { status == 401 || status == 429 }

    static func isCutShort(_ http: HTTPURLResponse, _ held: Data) -> Bool {
        guard http.value(forHTTPHeaderField: "Content-Encoding") == nil else { return false }
        let declared = http.expectedContentLength
        return declared > 0 && Int64(held.count) < declared
    }

    static func isUsageLimit(status: Int, body: Data) -> Bool {
        guard status == 429,
              let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let error = payload["error"] as? [String: Any] else { return false }
        return error["type"] as? String == usageLimit
    }

    static func refusal(_ message: String) -> Data {
        let payload: [String: Any] = [
            "error": [
                "type": "invalid_request_error",
                "code": "hats_gateway",
                "message": "Hats: " + message,
            ],
        ]
        let encoded = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return encoded ?? Data(#"{"error":{"type":"invalid_request_error","message":"Hats"}}"#.utf8)
    }

    static let needsSignIn = "the worn Codex hat needs a sign-in. Sign it in again in Hats, then retry."
    static let renewUnreachable = "the worn Codex hat's login could not be renewed just now. Try again."
    static let nothingWorn = "no Codex hat is worn. Put one on in Hats, then retry."
}
