import CryptoKit
import Foundation

enum GatewayPaths {
    static let control = "/__gateway__/status"

    static let sessionsAtRisk = "/__gateway__/sessions-at-risk"

    static let marker = "hats-gateway"

    static let inference: Set<String> = ["/v1/messages", "/v1/complete"]

    static let sessionHeader = "x-claude-code-session-id"

    static func isInference(_ path: String) -> Bool {
        inference.contains(String(path.split(separator: "?").first ?? ""))
    }

    static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "[::1]"]

    static func isFromLoopback(host: String?, boundTo port: Int) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let named: String
        let carried: String?
        if host.hasPrefix("[") {
            guard let close = host.firstIndex(of: "]") else { return false }
            named = String(host[...close])
            let rest = host[host.index(after: close)...]
            carried = rest.hasPrefix(":") ? String(rest.dropFirst()) : (rest.isEmpty ? nil : "")
        } else if let colon = host.lastIndex(of: ":") {
            named = String(host[..<colon])
            carried = String(host[host.index(after: colon)...])
        } else {
            named = host
            carried = nil
        }
        guard loopbackHosts.contains(named.lowercased()) else { return false }
        guard let carried else { return port == 80 }
        return Int(carried) == port
    }
}

enum GatewayCredential {
    static let none = "none"

    static func fingerprint(_ header: String?) -> String {
        guard let header, !header.isEmpty else { return none }
        let parts = header.split(
            separator: " ",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let raw = parts.count == 2 ? String(parts[1]) : String(parts[0])
        let token = raw.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return none }
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
