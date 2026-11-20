import XCTest
@testable import Hats

final class CodexGatewayPathsTests: XCTestCase {
    private let secret = String(repeating: "ab", count: 32)

    private func route(_ method: String, _ uri: String, upgrade: String? = nil) -> CodexGatewayRoute {
        CodexGatewayPaths.route(method: method, uri: uri, secret: secret, upgrade: upgrade)
    }

    func testEveryPathOfTheCodexModelProviderIsForwardedWithItsQuery() {
        XCTAssertEqual(route("GET", "/\(secret)/codex/models?client_version=0.169.0"),
                       .forward(path: "models", query: "client_version=0.169.0", isStream: false))
        XCTAssertEqual(route("POST", "/\(secret)/codex/responses"),
                       .forward(path: "responses", query: nil, isStream: true))
        for path in ["images/generations", "images/edits", "alpha/search", "memories/trace_summarize"] {
            XCTAssertEqual(route("POST", "/\(secret)/codex/\(path)"),
                           .forward(path: path, query: nil, isStream: false), path)
        }
    }

    func testOtherPathsAndOtherMethodsAreNotFound() {
        XCTAssertEqual(route("POST", "/\(secret)/codex/realtime/calls"), .notFound, "voice mode is not supported")
        XCTAssertEqual(route("POST", "/\(secret)/codex/models"), .notFound)
        XCTAssertEqual(route("GET", "/\(secret)/codex/responses"), .notFound)
        XCTAssertEqual(route("POST", "/\(secret)/codex/../wham/usage"), .notFound)
        XCTAssertEqual(route("POST", "/\(secret)/backend-api/codex/responses"), .notFound)
    }

    func testARequestWithoutTheRightSecretIsNotFound() {
        XCTAssertEqual(route("POST", "/codex/responses"), .notFound)
        XCTAssertEqual(route("POST", "/\(secret.dropLast())/codex/responses"), .notFound)
        XCTAssertEqual(route("POST", "/\(secret)x/codex/responses"), .notFound)
        XCTAssertEqual(route("POST", "/\(String(repeating: "cd", count: 32))/codex/responses"), .notFound,
                       "a secret of the same length that is not ours")
        XCTAssertEqual(route("GET", "/__gateway__/sessions-at-risk"), .notFound)
        XCTAssertEqual(CodexGatewayPaths.route(method: "POST", uri: "//codex/responses", secret: "", upgrade: nil),
                       .notFound, "an empty secret opens nothing")
    }

    func testAWebSocketHandshakeIsAnsweredWithUpgradeRequiredOnlyUnderTheSecret() {
        XCTAssertEqual(route("GET", "/\(secret)/codex/responses", upgrade: "websocket"), .upgradeRequired)
        XCTAssertEqual(route("GET", "/\(secret)/codex/responses", upgrade: "WebSocket"), .upgradeRequired)
        XCTAssertEqual(route("GET", "/codex/responses", upgrade: "websocket"), .notFound)
    }

    func testTheSessionsAtRiskPathLivesUnderTheSecret() {
        XCTAssertEqual(route("GET", "/\(secret)/__gateway__/sessions-at-risk"), .sessionsAtRisk)
        XCTAssertEqual(route("POST", "/\(secret)/__gateway__/sessions-at-risk"), .notFound)
    }

    func testTheAddressCarriesTheSecretAndIsRecognisedAsOursOnAnyPort() {
        let base = CodexGatewayPaths.baseURL(port: 8788, secret: secret)
        XCTAssertEqual(base, "http://127.0.0.1:8788/\(secret)/codex")
        XCTAssertFalse(base.hasSuffix("/backend-api/codex"), "Codex treats that suffix as the ChatGPT backend")
        XCTAssertTrue(CodexGatewayPaths.isOurs(base, secret: secret))
        XCTAssertTrue(CodexGatewayPaths.isOurs("http://127.0.0.1:9000/\(secret)/codex", secret: secret))
        XCTAssertFalse(CodexGatewayPaths.isOurs("http://127.0.0.1:8788/other/codex", secret: secret))
        XCTAssertTrue(CodexGatewayPaths.isOurs("http://127.0.0.1:8788/\(String(repeating: "0f", count: 32))/codex",
                                               secret: secret), "Hats' own line from before a secret reset")
        XCTAssertFalse(CodexGatewayPaths.isOurs("http://127.0.0.1:8788/\(String(repeating: "0F", count: 32))/codex",
                                                secret: secret))
        XCTAssertFalse(CodexGatewayPaths.isOurs("https://proxy.example/\(secret)/codex", secret: secret))
    }

    func testTheUpstreamAddressKeepsTheBackendPathAndTheQuery() throws {
        let url = CodexGatewayPaths.upstreamURL(base: CodexGatewayPaths.upstream, path: "models",
                                                query: "client_version=0.169.0")
        XCTAssertEqual(url?.absoluteString, "https://chatgpt.com/backend-api/codex/models?client_version=0.169.0")
    }

    func testABadlyEncodedQueryIsRefusedInsteadOfStoppingTheApp() {
        for query in ["a=%zz", "a=%", "a=b c", "a=|", "a=[x]", "a=\u{0}"] {
            XCTAssertNil(CodexGatewayPaths.upstreamURL(base: CodexGatewayPaths.upstream, path: "models", query: query),
                         "setting \(query) as an encoded query traps; the gateway answers that it cannot address it")
        }
        XCTAssertEqual(
            CodexGatewayPaths.upstreamURL(base: CodexGatewayPaths.upstream, path: "models", query: "a=%20b&c=d")?
                .absoluteString,
            "https://chatgpt.com/backend-api/codex/models?a=%20b&c=d"
        )
        XCTAssertNotNil(CodexGatewayPaths.upstreamURL(base: CodexGatewayPaths.upstream, path: "models", query: ""))
    }

    func testANewSecretIsLongEnoughAndUsable() {
        let one = CodexGatewayPaths.newSecret()
        XCTAssertGreaterThanOrEqual(one.count * 4, 128, "the secret carries at least 128 bits")
        XCTAssertTrue(CodexGatewayPaths.isAUsableSecret(one))
        XCTAssertNotEqual(one, CodexGatewayPaths.newSecret())
        XCTAssertFalse(CodexGatewayPaths.isAUsableSecret("short"))
        XCTAssertFalse(CodexGatewayPaths.isAUsableSecret(String(repeating: "Z", count: 64)))
    }

    func testTheSettingsKeepThePortAndTheSecretAndDropABadOne() throws {
        var settings = AppSettings()
        XCTAssertEqual(settings.codexGatewayPort, 8788)
        XCTAssertNil(settings.isCodexGatewayEnabled, "on by default once a Codex hat exists, decided by the app")
        settings.codexGatewaySecret = secret
        settings.isCodexGatewayEnabled = true
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.codexGatewaySecret, secret)
        XCTAssertEqual(back.isCodexGatewayEnabled, true)
        let bad = Data(#"{"codexGatewayPort": 80, "codexGatewaySecret": "../x"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: bad)
        XCTAssertEqual(decoded.codexGatewayPort, 8788)
        XCTAssertNil(decoded.codexGatewaySecret)
    }
}
