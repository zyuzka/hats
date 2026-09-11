import XCTest
@testable import Hats

final class TokenRenewalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheRequestIsTheOneTheCLIMakes() throws {
        let request = TokenRenewal.request(refreshToken: "r-1", scopes: [])
        XCTAssertEqual(request.url?.absoluteString, "https://platform.claude.com/v1/oauth/token",
                       "read out of the 2.1.260 bundle as TOKEN_URL; api.anthropic.com does not answer this")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json",
                       "the claude.ai grant is posted as JSON; the form encoding belongs to the gateway JWT path")
        let body = try XCTUnwrap(request.httpBody).map { $0 }
        let sent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(body)) as? [String: Any]
        )
        XCTAssertEqual(sent["grant_type"] as? String, "refresh_token")
        XCTAssertEqual(sent["refresh_token"] as? String, "r-1")
        XCTAssertEqual(sent["client_id"] as? String, "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        XCTAssertEqual(sent["scope"] as? String,
                       "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload")
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-beta"),
                     "the beta header belongs to the usage endpoint, and a copied header sends the "
                         + "next requester after the wrong shape")
    }

    func testTheScopesAlreadyStoredAreTheOnesAskedFor() throws {
        let request = TokenRenewal.request(refreshToken: "r-1", scopes: ["user:profile", "user:design:read"])
        let sent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(sent["scope"] as? String, "user:profile user:design:read",
                       "asking for the CLI's default list would narrow a credential that carries more, "
                           + "and the token it mints is what the hat has to live on")
    }

    func testATwoHundredWithATokenAndAnExpiryIsARenewal() throws {
        let body = Data(#"""
        {"access_token":"a-2","refresh_token":"r-2","expires_in":28800,
         "refresh_token_expires_in":2592000,"scope":"user:profile user:inference",
         "account":{"uuid":"u-1","email_address":"filip@example.com"}}
        """#.utf8)
        guard case .renewed(let login) = TokenRenewal.outcome(
            status: 200, body: body, keeping: "r-1", at: now
        ) else { return XCTFail("a complete answer is a renewal") }
        XCTAssertEqual(login.accessToken, "a-2")
        XCTAssertEqual(login.refreshToken, "r-2")
        XCTAssertEqual(login.expiresAt, now.addingTimeInterval(28800))
        XCTAssertEqual(login.refreshExpiresAt, now.addingTimeInterval(2_592_000))
        XCTAssertEqual(login.scopes, ["user:profile", "user:inference"])
        XCTAssertEqual(login.account, "filip@example.com",
                       "the answer names the account, so the journal can say whose login was renewed "
                           + "without a second request")
    }

    func testAnAnswerWithoutARotatedTokenKeepsTheOneItWasSent() throws {
        let body = Data(#"{"access_token":"a-2","expires_in":28800}"#.utf8)
        guard case .renewed(let login) = TokenRenewal.outcome(
            status: 200, body: body, keeping: "r-1", at: now
        ) else { return XCTFail("a missing refresh_token is not a failure") }
        XCTAssertEqual(login.refreshToken, "r-1",
                       "the CLI destructures refresh_token with the posted one as its default; storing "
                           + "an empty token here would lose the only copy the hat has")
        XCTAssertNil(login.refreshExpiresAt,
                     "and an absent refresh expiry must not overwrite the one already stored")
        XCTAssertEqual(login.scopes, [],
                       "an absent scope means keep what is stored, not narrow it to nothing")
        XCTAssertNil(login.account)
    }

    func testAnAnswerMissingTheTokenOrTheExpiryIsNotStored() {
        XCTAssertEqual(TokenRenewal.outcome(status: 200, body: Data(#"{"expires_in":28800}"#.utf8),
                                            keeping: "r-1", at: now),
                       .failed("the renewed login carries no token"))
        XCTAssertEqual(TokenRenewal.outcome(status: 200, body: Data(#"{"access_token":"","expires_in":1}"#.utf8),
                                            keeping: "r-1", at: now),
                       .failed("the renewed login carries no token"))
        XCTAssertEqual(TokenRenewal.outcome(status: 200, body: Data(#"{"access_token":"a-2"}"#.utf8),
                                            keeping: "r-1", at: now),
                       .failed("the renewed login carries no expiry"),
                       "a credential with no expiresAt reads as usable forever, so a token whose "
                           + "lifetime is unknown must not be written into the slot")
        XCTAssertEqual(TokenRenewal.outcome(status: 200, body: Data("not json".utf8),
                                            keeping: "r-1", at: now),
                       .failed("the renewal answer could not be read"))
        XCTAssertEqual(TokenRenewal.outcome(status: 200, body: nil, keeping: "r-1", at: now),
                       .failed("the renewal answer could not be read"))
    }

    func testOnlyTheServerSayingInvalidGrantMeansTheHatNeedsALogin() {
        let dead = Data(#"{"error":"invalid_grant","error_description":"refresh token expired"}"#.utf8)
        XCTAssertEqual(TokenRenewal.outcome(status: 400, body: dead, keeping: "r-1", at: now), .needsLogin)
        XCTAssertEqual(TokenRenewal.outcome(status: 401, body: dead, keeping: "r-1", at: now), .needsLogin)
        XCTAssertEqual(TokenRenewal.outcome(status: 400, body: Data(#"{"error":{"type":"invalid_grant"}}"#.utf8),
                                            keeping: "r-1", at: now),
                       .needsLogin,
                       "the CLI reads the code from a string error or from error.type, and both shapes arrive")
        XCTAssertEqual(TokenRenewal.outcome(status: 403, body: dead, keeping: "r-1", at: now),
                       .failed("http 403"),
                       "the CLI treats only 400 and 401 as a dead grant; a 403 is the account, not the token")
        XCTAssertEqual(TokenRenewal.outcome(status: 400, body: Data(#"{"error":"invalid_scope"}"#.utf8),
                                            keeping: "r-1", at: now),
                       .failed("http 400"))
        XCTAssertEqual(TokenRenewal.outcome(status: 401, body: nil, keeping: "r-1", at: now),
                       .failed("http 401"),
                       "a refusal with no body is not evidence the grant is dead, and telling a person "
                           + "to log in again on a blip costs them a login")
        XCTAssertEqual(TokenRenewal.outcome(status: 429, body: nil, keeping: "r-1", at: now),
                       .failed("http 429"))
        XCTAssertEqual(TokenRenewal.outcome(status: 500, body: nil, keeping: "r-1", at: now),
                       .failed("http 500"))
        XCTAssertEqual(TokenRenewal.outcome(status: 0, body: nil, keeping: "r-1", at: now),
                       .failed("unreachable"))
    }

    func testAWholeAndAFractionalLifetimeBothParse() {
        XCTAssertEqual(TokenRenewal.seconds(28800), 28800)
        XCTAssertEqual(TokenRenewal.seconds(28800.5), 28800.5)
        XCTAssertNil(TokenRenewal.seconds("28800"))
        XCTAssertNil(TokenRenewal.seconds(nil))
        XCTAssertNil(TokenRenewal.seconds(Double.nan))
    }

    func testALifetimeThatIsNotUsableIsRefusedRatherThanStored() {
        for unusable in [0, -1, -3600] {
            let body = Data("{\"access_token\":\"a-2\",\"expires_in\":\(unusable)}".utf8)
            XCTAssertEqual(TokenRenewal.outcome(status: 200, body: body, keeping: "r-1"),
                           .failed("the renewed login carries no expiry"),
                           "expires_in=\(unusable) puts the token's death at or before now, so a "
                               + "renewal would be attempted again on every poll; the absent case "
                               + "is already refused for exactly this reason")
        }
    }

    func testARefreshLifetimeThatIsNotUsableLeavesTheStoredOneAlone() throws {
        let body = Data("{\"access_token\":\"a-2\",\"expires_in\":28800,\"refresh_token_expires_in\":0}".utf8)
        guard case .renewed(let login) = TokenRenewal.outcome(status: 200, body: body, keeping: "r-1")
        else { return XCTFail("a usable access lifetime must still renew") }

        XCTAssertNil(login.refreshExpiresAt,
                     "0 would be written straight into the keychain and copied onto the hat, and "
                         + "isExpired reads refreshExpiresAt <= now — so the hat would lock itself "
                         + "out of switching immediately after a renewal the journal called done")
    }

    func testATrueWhereANumberBelongsIsNotReadAsOneSecond() {
        let body = Data("{\"access_token\":\"a-2\",\"expires_in\":true}".utf8)

        XCTAssertEqual(TokenRenewal.outcome(status: 200, body: body, keeping: "r-1"),
                       .failed("the renewed login carries no expiry"),
                       "JSONSerialization hands both numbers and booleans over as NSNumber, and a "
                           + "cast to Int takes true as 1 — a one-second login that renews itself "
                           + "on every poll")
    }
}
