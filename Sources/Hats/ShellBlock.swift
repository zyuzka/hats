import Foundation

extension ShellEnvironment {
    static let probeTimeoutSeconds = 1

    static let curlPath = "/usr/bin/curl"
    static let grepPath = "/usr/bin/grep"

    static func probe(baseURL: String) -> String {
        "\(curlPath) -sf --noproxy '*' -m \(probeTimeoutSeconds) \(baseURL)\(GatewayPaths.control)"
    }

    static func block(baseURL: String, dialect: ShellDialect) -> String {
        let exports = [
            dialect.exportLine(baseURLName, baseURL),
            dialect.exportLine("_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL", "1"),
            dialect.exportLine("CLAUDE_GATEWAY_ALLOW_LOOPBACK", "1"),
        ]
        let guarded = dialect.guarded(
            exports,
            byTheAnswerTo: probe(baseURL: baseURL),
            containing: GatewayPaths.marker
        )
        return ([openMarker] + guarded + [closeMarker]).joined(separator: "\n")
    }
}
