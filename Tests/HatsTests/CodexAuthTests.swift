import XCTest
@testable import Hats

final class CodexAuthTests: XCTestCase {
    private let work = CodexFixture.work

    func testTheOwnerIsTheUserAndTheAccountOfTheIDToken() throws {
        let token = CodexFixture.idToken(user: "u-1", account: "a-1", email: "Work@Example.com", plan: "plus")

        let identity = try XCTUnwrap(CodexIdentity.of(idToken: token))

        XCTAssertEqual(identity.owner, CodexOwner(userID: "u-1", accountID: "a-1"))
        XCTAssertEqual(identity.email, "Work@Example.com")
        XCTAssertEqual(identity.plan, "plus")
    }

    func testAnIDTokenWithoutAnAccountNamesNoOwner() {
        XCTAssertNil(CodexIdentity.of(idToken: CodexFixture.idToken(user: "u-1", account: nil, email: "w@e.com")))
        XCTAssertNil(CodexIdentity.of(idToken: "not.a-jwt"))
    }

    func testTheUserFallsBackToTheSubjectOnlyWhenTheClaimsNameNone() throws {
        let token = CodexFixture.jwt([
            CodexIdentity.authClaim: ["chatgpt_account_id": "a-2"],
            "sub": "auth0|someone",
        ])

        XCTAssertEqual(try XCTUnwrap(CodexIdentity.of(idToken: token)).owner.userID, "auth0|someone")
    }

    func testAFreshSignInIsWrittenWithTheFieldsCodexWrites() throws {
        let data = CodexFixture.login(work, refresh: "r-1")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tokens = try XCTUnwrap(root["tokens"] as? [String: Any])

        XCTAssertEqual(root["auth_mode"] as? String, "chatgpt")
        XCTAssertTrue(root["OPENAI_API_KEY"] is NSNull, "always present, null without an API key")
        XCTAssertNotNil(root["last_refresh"] as? String)
        XCTAssertEqual(Set(tokens.keys), [
            "id_token", "access_token", "refresh_token", "oauth_provenance", "login_owner_id", "account_id",
        ])
        XCTAssertEqual(tokens["account_id"] as? String, work.account)
        XCTAssertEqual(tokens["oauth_provenance"] as? [String: String], [
            "issuer": "https://auth.openai.com",
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
        ])
        XCTAssertNil(CodexAuth.problem(of: data))
    }

    func testTheProblemsOfALoginAreNamed() {
        XCTAssertEqual(CodexAuth.problem(of: Data("{".utf8)), .notJSON)
        XCTAssertEqual(CodexAuth.problem(of: Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"k"}"#.utf8)), .notChatGPT)
        XCTAssertEqual(CodexAuth.problem(of: Data(#"{"auth_mode":"chatgpt","tokens":{}}"#.utf8)), .noTokens)
        let ownerless = CodexAuth.signedIn(
            idToken: CodexFixture.idToken(user: "u", account: nil, email: "w@e.com"),
            accessToken: "a",
            refreshToken: "r",
            loginOwnerID: "o",
            at: CodexFixture.now
        )
        XCTAssertEqual(ownerless.problem, .noOwner)
    }

    func testARenewalReplacesOnlyTheTokensItBroughtAndKeepsTheRest() throws {
        let before = try XCTUnwrap(CodexAuth(data: CodexFixture.login(work, refresh: "r-1")))
        let later = CodexFixture.now.addingTimeInterval(3600)

        let after = before.renewed(idToken: nil, accessToken: "new-access", refreshToken: nil, at: later)

        XCTAssertEqual(after.accessToken, "new-access")
        XCTAssertEqual(after.refreshToken, "r-1", "an answer without a refresh token keeps the old one")
        XCTAssertEqual(after.idToken, before.idToken)
        XCTAssertEqual(after.tokens["login_owner_id"] as? String, "owner-r-1")
        XCTAssertEqual(after.tokens["account_id"] as? String, work.account)
        XCTAssertNotNil(after.tokens["oauth_provenance"])
        XCTAssertEqual(after.lastRefresh?.timeIntervalSince1970 ?? 0, later.timeIntervalSince1970, accuracy: 0.01)
    }

    func testTheRefreshStampIsReadWithAnyNumberOfFractionalDigits() {
        XCTAssertNotNil(CodexAuth.date("2026-11-18T10:00:00Z"))
        XCTAssertNotNil(CodexAuth.date("2026-11-18T10:00:00.123Z"))
        XCTAssertNotNil(CodexAuth.date("2026-11-18T10:00:00.123456789Z"), "chrono writes up to nine digits")
    }

    func testTheExpiryIsReadFromTheAccessToken() throws {
        let expiry = CodexFixture.now.addingTimeInterval(86_400)
        let auth = try XCTUnwrap(CodexAuth(data: CodexFixture.login(work, refresh: "r", expiresAt: expiry)))

        XCTAssertEqual(auth.accessExpiry, expiry)
        XCTAssertNil(CodexJWT.expiry(CodexFixture.jwt(["exp": true])), "a boolean is not a time")
    }
}
