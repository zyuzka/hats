import XCTest
@testable import Hats

final class RelaySessionsCopyTests: XCTestCase {
    private func row(_ session: String, credential: String = "cc464558") -> GatewaySessionRow {
        GatewaySessionRow(
            session: session,
            requests: 1,
            lastStatus: 200,
            lastSeen: .now,
            credential: credential
        )
    }

    func testAnOffRelayIsSaidToBeSeeingNothing() {
        XCTAssertEqual(HatsCopy.relaySessions([row("aaa")], serving: false),
                       "The relay is off, so it is seeing nothing",
                       "rows left over from before it stopped must not read as current traffic")
    }

    func testAServingRelayWithNothingYetSaysSo() {
        XCTAssertEqual(HatsCopy.relaySessions([], serving: true),
                       "The relay has served no session yet")
    }

    func testOneSessionIsNotToldItIsAloneOnItsCredential() {
        XCTAssertEqual(HatsCopy.relaySessions([row("aaa")], serving: true),
                       "1 session through the relay",
                       "with one session the credential count says nothing worth saying")
    }

    func testSeveralSessionsOnOneCredentialSayThat() {
        let rows = [row("aaa"), row("bbb"), row("ccc")]
        XCTAssertEqual(HatsCopy.relaySessions(rows, serving: true),
                       "3 sessions through the relay, all on one credential",
                       "this is the case the count per credential could never show")
    }

    func testSeveralCredentialsAreCounted() {
        let rows = [row("aaa", credential: "1111"), row("bbb", credential: "2222"), row("ccc", credential: "2222")]
        XCTAssertEqual(HatsCopy.relaySessions(rows, serving: true),
                       "3 sessions through the relay on 2 credentials")
    }

    func testAnUnidentifiedSessionIsNamedRatherThanTruncated() {
        XCTAssertEqual(HatsCopy.shortSession(GatewayRefusal.unidentifiedSession), "unidentified",
                       "a dash in a table column reads as missing data rather than as its own case")
    }

    func testASessionIdIsShortenedToSomethingComparable() {
        XCTAssertEqual(HatsCopy.shortSession("a2df3a29-03f4-412c-a7de-6cbbb16fb2e5"), "a2df3a29")
        XCTAssertEqual(HatsCopy.shortSession("abc"), "abc", "a short id is not padded or cut further")
    }

    func testTheExplanationNamesBothQuestions() {
        let text = HatsCopy.theTwoSessionListsDiffer
        XCTAssertTrue(text.contains("alive now"), "the first list is processes that exist")
        XCTAssertTrue(text.contains("since ended"), "the second includes sessions that no longer exist")
        XCTAssertTrue(text.contains("need not agree"),
                      "without this the reader treats a mismatch between the two tables as a defect")
    }

    func testTheSentenceStopsClaimingEverySessionEverServed() {
        XCTAssertTrue(HatsCopy.theTwoSessionListsDiffer.contains("\(GatewaySessions.kept) most recently seen"),
                      "the ledger keeps 32 and evicts the oldest, so promising every session since "
                          + "it started was deterministically false past the 33rd")
        XCTAssertTrue(HatsCopy.theTwoSessionListsDiffer.contains("older ones are dropped"))
    }

    func testAFullTableSaysMostRecentRatherThanATotal() {
        let full = (1...GatewaySessions.kept).map {
            GatewaySessionRow(session: "s\($0)", requests: 1, lastStatus: 200,
                              lastSeen: .now, credential: "c")
        }
        XCTAssertTrue(HatsCopy.relaySessions(full, serving: true).contains("most recent"),
                      "at the cap the count is the rows kept, not the sessions served")

        let few = Array(full.prefix(2))
        XCTAssertTrue(HatsCopy.relaySessions(few, serving: true).contains("2 sessions"),
                      "below the cap the plain count is still the honest one")
    }
}
