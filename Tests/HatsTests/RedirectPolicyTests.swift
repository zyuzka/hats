import XCTest
@testable import Hats

final class RedirectPolicyTests: XCTestCase {
    private func url(_ text: String) -> URL { URL(string: text) ?? URL(fileURLWithPath: "/") }

    func testARedirectThatStaysWhereItStartedIsAllowed() {
        XCTAssertTrue(RedirectPolicy.isTheSameOrigin(
            url("https://platform.claude.com/v1/oauth/token"),
            url("https://platform.claude.com/v1/oauth/token/")
        ), "a path-only redirect on the same origin is ordinary and must not be refused")
    }

    func testAnotherHostIsRefused() {
        XCTAssertFalse(RedirectPolicy.isTheSameOrigin(
            url("https://platform.claude.com/v1/oauth/token"),
            url("https://elsewhere.example.com/v1/oauth/token")
        ), "a 307 or 308 keeps the method and the body, so following this one would post a "
            + "long-lived refresh token to whoever the redirect names")
    }

    func testDroppingToPlainHTTPIsRefusedEvenOnTheSameHost() {
        XCTAssertFalse(RedirectPolicy.isTheSameOrigin(
            url("https://platform.claude.com/v1/oauth/token"),
            url("http://platform.claude.com/v1/oauth/token")
        ), "same host, and the token would go out in clear — a downgrade is the second door of "
            + "this class and a host check alone walks past it")
    }

    func testAnotherPortIsRefused() {
        XCTAssertFalse(RedirectPolicy.isTheSameOrigin(
            url("https://platform.claude.com/token"),
            url("https://platform.claude.com:8443/token")
        ))
    }

    func testTheHostIsComparedWithoutCase() {
        XCTAssertTrue(RedirectPolicy.isTheSameOrigin(
            url("https://Platform.Claude.COM/token"),
            url("https://platform.claude.com/other")
        ), "host names are case-insensitive, and refusing on case alone would break a real redirect")
    }

    func testAMissingUrlOnEitherSideIsRefused() {
        XCTAssertFalse(RedirectPolicy.isTheSameOrigin(nil, url("https://platform.claude.com")))
        XCTAssertFalse(RedirectPolicy.isTheSameOrigin(url("https://platform.claude.com"), nil))
        XCTAssertFalse(RedirectPolicy.isTheSameOrigin(nil, nil),
                       "a comparison that cannot be made is not a comparison that passed")
    }

    func testTheSharedSessionActuallyCarriesTheDelegate() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/OneShotRequest.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        XCTAssertTrue(text.contains("delegate: redirects"),
                      "the policy only exists where the session is told about it, and a session "
                          + "built as URLSession(configuration:) follows redirects by default with "
                          + "nothing consulted — which is what this whole file exists to stop")
    }
}
