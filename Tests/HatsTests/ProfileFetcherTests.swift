import XCTest
@testable import Hats

final class ProfileFetcherTests: XCTestCase {
    private let body = Data(#"""
    {"account":{"uuid":"11111111-2222-3333-4444-555555555555",
                "full_name":"Someone","display_name":"Someone",
                "email":"someone@example.co",
                "created_at":"2026-04-28T10:04:57.932214Z"},
     "organization":{"uuid":"66666666-7777-8888-9999-000000000000",
                     "name":"SomeOrg","organization_type":"claude_team"},
     "application":{"slug":"claude-code"},"enabled_plugins":[]}
    """#.utf8)

    func testTheRequestIsTheOneTheCLIMakes() throws {
        let request = ProfileFetcher.request(token: "tok-123")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/profile")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache",
                       "the CLI asks for no cached profile, and a cached answer would defeat the check")
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-beta"),
                     "unlike /api/oauth/usage this endpoint answered 200 without the beta header, measured 2026-09-03")
    }

    func testOnlyATwoHundredWithAnAccountIsAnIdentity() {
        XCTAssertEqual(ProfileFetcher.outcome(status: 200, body: body).identity?.email,
                       "someone@example.co")
        XCTAssertNil(ProfileFetcher.outcome(status: 401, body: body).identity,
                     "a refused token's body is an error document, not an identity")
        XCTAssertEqual(ProfileFetcher.outcome(status: 200, body: Data("not json".utf8)), .unreadable)
        XCTAssertEqual(ProfileFetcher.outcome(status: 200, body: nil), .unreadable)
    }

    func testAFailedFetchSaysWhichWayItFailed() {
        XCTAssertEqual(ProfileFetcher.outcome(status: 401, body: body), .refused(401),
                       "a revoked token is a different diagnosis from a network blip")
        XCTAssertEqual(ProfileFetcher.outcome(status: 403, body: nil), .refused(403))
        XCTAssertEqual(ProfileFetcher.outcome(status: 500, body: nil), .errored(500),
                       "a server error is not a refused token, and the journal must not say it is")
        XCTAssertEqual(ProfileFetcher.outcome(status: 429, body: nil), .errored(429))
        XCTAssertEqual(ProfileFetcher.outcome(status: 0, body: nil), .unreachable)
        XCTAssertNil(ProfileFetcher.outcome(status: 200, body: body).trouble)
        XCTAssertEqual(ProfileFetch.refused(401).trouble, "refused 401")
        XCTAssertEqual(ProfileFetch.errored(429).trouble, "http 429")
        XCTAssertEqual(ProfileFetch.unreachable.trouble, "unreachable")
        XCTAssertEqual(ProfileFetch.unreadable.trouble, "unreadable")
    }

    func testABodyWithoutBothIdentifyingFieldsIsNotAnIdentity() {
        let noEmail = Data(#"{"account":{"uuid":"11111111-2222"}}"#.utf8)
        let noUUID = Data(#"{"account":{"email":"someone@example.co"}}"#.utf8)
        let blankEmail = Data(#"{"account":{"uuid":"11111111","email":"  "}}"#.utf8)
        XCTAssertEqual(ProfileFetcher.outcome(status: 200, body: noEmail), .unreadable,
                       "without an address the answer cannot be compared to a hat")
        XCTAssertEqual(ProfileFetcher.outcome(status: 200, body: noUUID), .unreadable,
                       "the uuid is the field the usage defect is about, so an answer missing it is not usable")
        XCTAssertEqual(ProfileFetcher.outcome(status: 200, body: blankEmail), .unreadable)
        XCTAssertEqual(ProfileFetcher.outcome(status: 200, body: Data("{}".utf8)), .unreadable)
    }
}
