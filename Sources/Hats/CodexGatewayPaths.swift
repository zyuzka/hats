import Foundation
import Security

enum CodexGatewayRoute: Equatable {
    case notFound
    case upgradeRequired
    case sessionsAtRisk
    case forward(path: String, query: String?, isStream: Bool)
}

enum CodexGatewayPaths {
    static let upstream = URL(string: "https://chatgpt.com/backend-api/codex") ?? URL(fileURLWithPath: "/")
    static let sessionsAtRisk = "__gateway__/sessions-at-risk"
    static let defaultPort = 8788
    static let streamed = "responses"

    static let forwarded: [String: String] = [
        "models": "GET",
        "responses": "POST",
        "images/generations": "POST",
        "images/edits": "POST",
        "alpha/search": "POST",
        "memories/trace_summarize": "POST",
    ]

    static func baseURL(port: Int, secret: String) -> String {
        "http://127.0.0.1:\(port)/\(secret)/codex"
    }

    static func isOurs(_ value: String, secret: String) -> Bool {
        guard let parsed = URLComponents(string: value), parsed.scheme == "http",
              parsed.host == "127.0.0.1", parsed.port != nil, parsed.query == nil else { return false }
        if parsed.path == "/\(secret)/codex" { return true }
        let parts = parsed.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].isEmpty, parts[2] == "codex" else { return false }
        return parts[1].count == 64 && parts[1].allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) }
    }

    static func route(method: String, uri: String, secret: String, upgrade: String?) -> CodexGatewayRoute {
        let parts = uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(parts.first ?? "")
        let query = parts.count == 2 ? String(parts[1]) : nil
        let prefix = "/\(secret)/"
        guard !secret.isEmpty, path.count > prefix.count,
              hasTheSameSecret(String(path.prefix(prefix.count)), prefix) else { return .notFound }
        let rest = String(path.dropFirst(prefix.count))
        if rest == sessionsAtRisk { return method == "GET" ? .sessionsAtRisk : .notFound }
        guard rest.hasPrefix("codex/") else { return .notFound }
        if method == "GET", upgrade?.lowercased().contains("websocket") == true { return .upgradeRequired }
        let sub = String(rest.dropFirst("codex/".count))
        guard forwarded[sub] == method else { return .notFound }

        return .forward(path: sub, query: query, isStream: sub == streamed)
    }

    static func hasTheSameSecret(_ given: String, _ expected: String) -> Bool {
        let left = Array(given.utf8)
        let right = Array(expected.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }

        return difference == 0
    }

    static func upstreamURL(base: URL, path: String, query: String?) -> URL? {
        var built = URLComponents(url: base, resolvingAgainstBaseURL: false)
        let root = built?.percentEncodedPath ?? ""
        built?.percentEncodedPath = (root.hasSuffix("/") ? root : root + "/") + path
        built?.percentEncodedQuery = query

        return built?.url
    }

    static func isAUsableSecret(_ secret: String) -> Bool {
        secret.count >= 32 && secret.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) }
    }

    static func newSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        }

        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
