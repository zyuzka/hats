import XCTest
@testable import Hats

final class UsageFetcherTests: XCTestCase {
    func testTheRequestIsTheOneTheCLIMakes() throws {
        let request = UsageFetcher.request(token: "tok-123")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20",
                       "the oauth endpoints answer only behind this beta header")
    }

    func testOnlyATwoHundredWithAParsableBodyIsAReading() {
        let body = Data(#"{"five_hour":{"utilization":26,"resets_at":"2026-08-30T12:50:00Z"}}"#.utf8)
        XCTAssertEqual(UsageFetcher.reading(status: 200, body: body)?.session?.percent, 26)
        XCTAssertNil(UsageFetcher.reading(status: 401, body: body),
                     "a refused token's body is an error document, not a reading")
        XCTAssertNil(UsageFetcher.reading(status: 200, body: Data("not json".utf8)))
        XCTAssertNil(UsageFetcher.reading(status: 200, body: nil))
    }

    func testAFailedFetchSaysWhichWayItFailed() {
        let body = Data(#"{"five_hour":{"utilization":26,"resets_at":"2026-08-30T12:50:00Z"}}"#.utf8)
        XCTAssertEqual(UsageFetcher.outcome(status: 401, body: body), .refused(401),
                       "a revoked token is a different diagnosis from a network blip, and the journal must be able to tell")
        XCTAssertEqual(UsageFetcher.outcome(status: 200, body: Data("not json".utf8)), .unreadable)
        XCTAssertEqual(UsageFetcher.outcome(status: 200, body: nil), .unreadable)
        XCTAssertEqual(UsageFetcher.outcome(status: 0, body: nil), .unreachable)
        XCTAssertEqual(UsageFetcher.outcome(status: 200, body: body).reading?.session?.percent, 26)
        XCTAssertNil(UsageFetcher.outcome(status: 200, body: body).trouble)
        XCTAssertEqual(UsageFetch.refused(401).trouble, "refused 401")
        XCTAssertEqual(UsageFetcher.outcome(status: 403, body: nil), .refused(403))
        XCTAssertEqual(UsageFetcher.outcome(status: 500, body: nil), .errored(500),
                       "a server error is not a refused token, and the journal must not say it is")
        XCTAssertEqual(UsageFetcher.outcome(status: 429, body: nil), .errored(429))
        XCTAssertEqual(UsageFetch.errored(429).trouble, "http 429")
    }

    func testACredentialWithoutAUsableTokenYieldsNoRequest() {
        let expired = CredentialPayload(raw: Data(#"""
        {"claudeAiOauth":{"accessToken":"t","expiresAt":1000}}
        """#.utf8))
        XCTAssertFalse(expired.hasAUsableAccessToken(at: Date(timeIntervalSince1970: 2)))
        XCTAssertTrue(expired.hasAUsableAccessToken(at: Date(timeIntervalSince1970: 0.5)),
                      "expiresAt is milliseconds; before it the token is usable")
        let blank = CredentialPayload(raw: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8))
        XCTAssertFalse(blank.hasAUsableAccessToken())
        let none = CredentialPayload(raw: Data(#"{"mcpOAuth":{}}"#.utf8))
        XCTAssertFalse(none.hasAUsableAccessToken())
        XCTAssertNil(none.accessToken)
    }
}
