import XCTest
@testable import Hats

final class TokenIdentityTests: XCTestCase {
    private let mine = TokenIdentity(
        email: "someone@example.co",
        accountUUID: "11111111-2222-3333-4444-555555555555",
        organizationUUID: "66666666-7777-8888-9999-000000000000",
        organizationName: "SomeOrg"
    )

    private func payload(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    func testTheOrganizationIsOptionalAndTheAccountIsNot() {
        let withoutOrg = TokenIdentity.parsed(payload(#"""
        {"account":{"uuid":"11111111","email":"someone@example.co"}}
        """#))
        XCTAssertEqual(withoutOrg?.email, "someone@example.co")
        XCTAssertNil(withoutOrg?.organizationName,
                     "an answer that names the account but not the organization still identifies the token")
        XCTAssertNil(TokenIdentity.parsed(payload(#"{"organization":{"name":"SomeOrg"}}"#)),
                     "an organization alone does not say which account the token belongs to")
    }

    func testTheAddressIsTrimmedTheWayStoredAddressesAre() {
        let padded = TokenIdentity.parsed(payload(#"""
        {"account":{"uuid":"  11111111 ","email":"  someone@example.co\n"}}
        """#))
        XCTAssertEqual(padded?.email, "someone@example.co")
        XCTAssertEqual(padded?.accountUUID, "11111111")
    }

    func testTheVerdictComparesAddressesTheWayTheAppComparesThemElsewhere() {
        XCTAssertEqual(IdentityVerdict(expecting: "someone@example.co", fetch: .identity(mine)),
                       .confirmed(mine))
        XCTAssertEqual(IdentityVerdict(expecting: "  SOMEONE@Example.CO ", fetch: .identity(mine)),
                       .confirmed(mine),
                       "case and padding are not a mismatch: Account.sameAddress governs everywhere else")
        XCTAssertEqual(IdentityVerdict(expecting: "other@example.co", fetch: .identity(mine)),
                       .mismatch(expected: "other@example.co", actual: mine))
        XCTAssertTrue(IdentityVerdict(expecting: "other@example.co", fetch: .identity(mine)).isMismatch)
        XCTAssertFalse(IdentityVerdict(expecting: "someone@example.co", fetch: .identity(mine)).isMismatch)
    }

    func testAFetchThatDidNotAnswerIsUncheckedRatherThanAMismatch() {
        for fetch: ProfileFetch in [.unreachable, .unreadable, .refused(401), .errored(500)] {
            let verdict = IdentityVerdict(expecting: "someone@example.co", fetch: fetch)
            XCTAssertFalse(verdict.isMismatch,
                           "a switch whose check could not run has not been shown to be wrong")
            XCTAssertEqual(verdict, .unchecked(fetch.trouble ?? "unreadable"),
                           "the reason has to survive into the journal, not collapse into one word")
        }
        XCTAssertEqual(IdentityVerdict(expecting: "a@b.co", fetch: .unreachable).reading,
                       "unchecked:unreachable")
    }

    func testTheJournalLineNamesBothSidesAndTheVerdict() {
        let confirmed = IdentityVerdict.confirmed(mine)
            .journalled(at: "activate", expecting: "someone@example.co")
        XCTAssertEqual(confirmed["at"], "activate")
        XCTAssertEqual(confirmed["expected"], "someone@example.co")
        XCTAssertEqual(confirmed["tokenSays"], "someone@example.co")
        XCTAssertEqual(confirmed["tokenAccount"], "11111111-2222-3333-4444-555555555555",
                       "the uuid is recorded because a matching uuid is what the usage defect turns on")
        XCTAssertEqual(confirmed["tokenOrg"], "SomeOrg")
        XCTAssertEqual(confirmed["verdict"], "confirmed")

        let mismatch = IdentityVerdict.mismatch(expected: "other@example.co", actual: mine)
            .journalled(at: "capture", expecting: "other@example.co")
        XCTAssertEqual(mismatch["verdict"], "MISMATCH",
                       "the one line that means the slot holds somebody else has to be greppable")
        XCTAssertEqual(mismatch["tokenSays"], "someone@example.co")
        XCTAssertEqual(mismatch["expected"], "other@example.co")

        let unchecked = IdentityVerdict.unchecked("no usable token")
            .journalled(at: "activate", expecting: "someone@example.co")
        XCTAssertEqual(unchecked["tokenSays"], "-")
        XCTAssertEqual(unchecked["tokenAccount"], "-")
        XCTAssertEqual(unchecked["verdict"], "unchecked:no usable token")
    }

    func testACredentialWithNoUsableTokenMakesNoRequestAtAll() {
        var asked: [String] = []
        let fetching: (String) -> ProfileFetch = {
            asked.append($0)
            return .identity(self.mine)
        }
        let expired = CredentialPayload(raw: Data(#"""
        {"claudeAiOauth":{"accessToken":"t","expiresAt":1000}}
        """#.utf8))
        XCTAssertEqual(
            IdentityCheck.of("someone@example.co", credential: expired, fetching: fetching),
            .unchecked("no usable token"))
        let blank = CredentialPayload(raw: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8))
        XCTAssertEqual(
            IdentityCheck.of("someone@example.co", credential: blank, fetching: fetching),
            .unchecked("no usable token"))
        XCTAssertEqual(asked, [],
                       "an unusable token must not become a request: the check is free when it cannot run")
    }

    func testAUsableTokenIsTheOneHandedToTheFetcher() {
        var asked: [String] = []
        let fetching: (String) -> ProfileFetch = {
            asked.append($0)
            return .identity(self.mine)
        }
        let live = CredentialPayload(raw: Data(#"""
        {"claudeAiOauth":{"accessToken":"live-token"}}
        """#.utf8))
        XCTAssertEqual(
            IdentityCheck.of("someone@example.co", credential: live, fetching: fetching),
            .confirmed(mine))
        XCTAssertEqual(asked, ["live-token"],
                       "the token asked about is the one in the blob just written to the slot")
    }
}
