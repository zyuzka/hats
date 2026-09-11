import XCTest
@testable import Hats

final class CredentialRewriteTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var stored: Data {
        Data(#"""
        {"claudeAiOauth":{"accessToken":"a-1","refreshToken":"r-1","expiresAt":1000,
         "refreshTokenExpiresAt":2000,"scopes":["user:profile"],"subscriptionType":"max",
         "rateLimitTier":"tier-4","clientId":"9d1c250a-e61b-44d9-88ed-5944d1962f5e"},
         "mcpOAuth":{"linear":{"accessToken":"m-1"}},"somethingWeDoNotKnowAbout":7}
        """#.utf8)
    }

    private func renewed(refreshToken: String = "r-2",
                         refreshExpiresAt: Date? = nil,
                         scopes: [String] = []) -> RenewedLogin {
        RenewedLogin(accessToken: "a-2",
                     refreshToken: refreshToken,
                     expiresAt: now,
                     refreshExpiresAt: refreshExpiresAt,
                     scopes: scopes,
                     account: nil)
    }

    private func oauth(in data: Data) throws -> [String: Any] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["claudeAiOauth"] as? [String: Any])
    }

    func testTheRenewedTokenLandsInMillisecondsBecauseThatIsWhatTheBlobHolds() throws {
        let merged = try XCTUnwrap(CredentialRewrite.merged(stored, with: renewed()))
        let block = try oauth(in: merged)
        XCTAssertEqual(block["accessToken"] as? String, "a-2")
        XCTAssertEqual(block["refreshToken"] as? String, "r-2")
        XCTAssertEqual(block["expiresAt"] as? Int, 1_800_000_000_000,
                       "CredentialPayload divides expiresAt by 1000, so writing seconds would make "
                           + "every renewed token read as expired in 1970")
        XCTAssertEqual(CredentialPayload(raw: merged).accessExpires, now)
        XCTAssertTrue(CredentialPayload(raw: merged).hasAUsableAccessToken(at: now.addingTimeInterval(-1)))
    }

    func testEverythingTheAnswerDidNotMentionSurvives() throws {
        let merged = try XCTUnwrap(CredentialRewrite.merged(stored, with: renewed()))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: merged) as? [String: Any])
        XCTAssertEqual(CredentialPayload(raw: merged).mcpKeys, ["linear"],
                       "the MCP tokens live in the same credential, and a rewrite that rebuilt the "
                           + "blob would sign the person out of every MCP server they had")
        XCTAssertEqual(object["somethingWeDoNotKnowAbout"] as? Int, 7,
                       "a key this app has never heard of belongs to the CLI, not to us")
        let block = try oauth(in: merged)
        XCTAssertEqual(block["subscriptionType"] as? String, "max")
        XCTAssertEqual(block["rateLimitTier"] as? String, "tier-4")
        XCTAssertEqual(block["clientId"] as? String, "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        XCTAssertEqual(block["refreshTokenExpiresAt"] as? Int, 2000,
                       "an answer with no refresh_token_expires_in must leave the stored one alone, "
                           + "which is what the CLI's own store does")
        XCTAssertEqual(block["scopes"] as? [String], ["user:profile"],
                       "and an answer with no scope must not empty the list")
    }

    func testWhatTheAnswerDoesMentionReplacesWhatWasThere() throws {
        let merged = try XCTUnwrap(CredentialRewrite.merged(
            stored,
            with: renewed(refreshExpiresAt: now.addingTimeInterval(60), scopes: ["user:inference"])
        ))
        let block = try oauth(in: merged)
        XCTAssertEqual(block["refreshTokenExpiresAt"] as? Int, 1_800_000_060_000)
        XCTAssertEqual(block["scopes"] as? [String], ["user:inference"])
    }

    func testACredentialWithNoOAuthBlockGetsOneRatherThanBeingRefused() throws {
        let merged = try XCTUnwrap(CredentialRewrite.merged(Data(#"{"mcpOAuth":{}}"#.utf8), with: renewed()))
        XCTAssertEqual(try oauth(in: merged)["accessToken"] as? String, "a-2")
    }

    func testSomethingThatIsNotAJSONObjectIsNotRewritten() {
        XCTAssertNil(CredentialRewrite.merged(Data("not json".utf8), with: renewed()))
        XCTAssertNil(CredentialRewrite.merged(Data("[1,2]".utf8), with: renewed()))
        XCTAssertNil(CredentialRewrite.merged(Data(), with: renewed()))
    }

    func testTheSlotIsOnlyOursToWriteWhileItStillHoldsTheTokenWeSent() {
        XCTAssertTrue(CredentialRewrite.matches("r-1", in: stored))
        XCTAssertFalse(CredentialRewrite.matches("r-0", in: stored),
                       "a switch parked another login here while the renewal was in flight; that blob "
                           + "is newer than ours and overwriting it would undo the switch")
        XCTAssertFalse(CredentialRewrite.matches("r-1", in: Data(#"{"claudeAiOauth":{"refreshToken":""}}"#.utf8)),
                       "a slot that no longer carries a refresh token is a slot that MOVED. The CLI's "
                           + "own compare-and-swap treats empty as writable, and that rule was copied "
                           + "here where its premise does not hold: the CLI is filling the slot it just "
                           + "posted from, while this is a parked slot another operation may have "
                           + "replaced. Splicing the old renewal into it would revive a login the "
                           + "person had just cleared")
        XCTAssertFalse(CredentialRewrite.matches("r-1", in: Data(#"{"mcpOAuth":{}}"#.utf8)),
                       "and a payload with no oauth block at all is not the one we read from")
    }
}
