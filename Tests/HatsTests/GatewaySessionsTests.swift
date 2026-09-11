import XCTest
@testable import Hats

final class GatewaySessionsTests: XCTestCase {
    private let epoch = ContinuousClock.now

    private func noting(
        _ rows: [String: GatewaySessionRow],
        _ session: String,
        credential: String = "cc464558",
        status: Int = 200,
        after seconds: TimeInterval = 0,
        kept: Int = GatewaySessions.kept
    ) -> [String: GatewaySessionRow] {
        GatewaySessions.noting(
            rows,
            session: session,
            credential: credential,
            status: status,
            at: epoch.advanced(by: .seconds(seconds)),
            kept: kept
        )
    }

    func testTwoSessionsOnOneCredentialAreTwoRows() {
        var rows = noting([:], "aaa")
        rows = noting(rows, "bbb")
        XCTAssertEqual(rows.count, 2,
                       "this is the whole point: one token, two sessions, and the report has to say two")
        XCTAssertEqual(rows["aaa"]?.credential, "cc464558")
        XCTAssertEqual(rows["bbb"]?.credential, "cc464558")
    }

    func testASecondRequestCountsAgainstTheSameRow() {
        var rows = noting([:], "aaa", status: 200)
        rows = noting(rows, "aaa", credential: "9f31", status: 401, after: 5)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows["aaa"]?.requests, 2)
        XCTAssertEqual(rows["aaa"]?.lastStatus, 401)
        XCTAssertEqual(rows["aaa"]?.credential, "9f31",
                       "the row carries the credential it is running on now, not the one it started with")
        XCTAssertEqual(rows["aaa"]?.lastSeen, epoch.advanced(by: .seconds(5)))
    }

    func testARequestWithoutASessionHeaderKeepsTheExistingConvention() {
        let rows = noting([:], GatewayRefusal.sessionKey(nil))
        XCTAssertEqual(rows.count, 1)
        XCTAssertNotNil(rows[GatewayRefusal.unidentifiedSession],
                        "an unidentified request goes under the same dash the refusal already uses")
    }

    func testTheOldestRowIsTheOneEvicted() {
        var rows: [String: GatewaySessionRow] = [:]
        for i in 0..<4 {
            rows = noting(rows, "s\(i)", after: TimeInterval(i), kept: 3)
        }
        XCTAssertEqual(rows.count, 3)
        XCTAssertNil(rows["s0"], "s0 was seen first, so it is the one that goes")
        XCTAssertNotNil(rows["s3"])
    }

    func testEvictionIsDecidedByLastSeenAndNotByArrival() {
        var rows: [String: GatewaySessionRow] = [:]
        rows = noting(rows, "old", after: 0, kept: 2)
        rows = noting(rows, "middle", after: 1, kept: 2)
        rows = noting(rows, "old", after: 10, kept: 2)
        rows = noting(rows, "new", after: 11, kept: 2)
        XCTAssertNil(rows["middle"], "middle arrived second but was seen longest ago")
        XCTAssertNotNil(rows["old"])
        XCTAssertNotNil(rows["new"])
    }

    func testATieOnLastSeenIsBrokenByName() {
        var rows: [String: GatewaySessionRow] = [:]
        rows = noting(rows, "bbb", after: 0, kept: 1)
        rows = noting(rows, "aaa", after: 0, kept: 1)
        XCTAssertEqual(Array(rows.keys), ["bbb"],
                       "with equal timestamps the choice still has to be the same on every run")
    }

    func testKeepingNothingKeepsNothing() {
        let rows = noting([:], "aaa", kept: 0)
        XCTAssertTrue(rows.isEmpty)
    }

    func testTheReportPutsTheMostRecentlySeenFirst() {
        var rows: [String: GatewaySessionRow] = [:]
        rows = noting(rows, "first", after: 0)
        rows = noting(rows, "second", after: 30)
        let report = GatewaySessions.reported(rows, now: epoch.advanced(by: .seconds(30)))
        XCTAssertEqual(report.map { $0["session"] as? String }, ["second", "first"])
        XCTAssertEqual(report.first?["seconds_since_last"] as? Double, 0)
        XCTAssertEqual(report.last?["seconds_since_last"] as? Double, 30)
    }

    func testTheReportCarriesTheCountAndTheStatusPerSession() {
        var rows = noting([:], "aaa", status: 200)
        rows = noting(rows, "aaa", status: 429, after: 1)
        let row = GatewaySessions.reported(rows, now: epoch.advanced(by: .seconds(1))).first
        XCTAssertEqual(row?["requests"] as? Int, 2)
        XCTAssertEqual(row?["last_status"] as? Int, 429)
        XCTAssertEqual(row?["credential"] as? String, "cc464558")
    }

    func testAnIdAClientSendsCannotBecomeTheAnonymousRow() {
        XCTAssertNotEqual(GatewayRefusal.sessionKey("-"), GatewayRefusal.unidentifiedSession,
                          "a client sending a literal dash used to merge into the anonymous row and "
                              + "have its traffic counted as nobody's — and this case asserted that "
                              + "merge while its own name said it must not happen")
        XCTAssertNotEqual(GatewayRefusal.sessionKey(GatewayRefusal.unidentifiedSession),
                          GatewayRefusal.unidentifiedSession,
                          "the sentinel itself, fed back through the sanitiser, must not come out "
                              + "the other side: that is what makes it unforgeable rather than "
                              + "merely special-cased")
        XCTAssertEqual(GatewayRefusal.sessionKey(nil), GatewayRefusal.unidentifiedSession)
        XCTAssertEqual(GatewayRefusal.sessionKey(""), GatewayRefusal.unidentifiedSession)
    }

    func testAnIdIsReducedRatherThanChecked() {
        XCTAssertEqual(GatewayRefusal.sessionKey("abc-DEF_123"), "abc-DEF_123",
                       "the shape a session id really has survives untouched")
        XCTAssertEqual(GatewayRefusal.sessionKey("a b\nc"), "a.b.c",
                       "anything else is mapped, not rejected, so there is nothing left to escape with")
        XCTAssertEqual(GatewayRefusal.sessionKey(String(repeating: "x", count: 500)).count,
                       GatewayRefusal.sessionIdCap,
                       "an unbounded id from a header must not become an unbounded map key")
    }

    func testAnOlderCompletionCannotRollTheRowBackOntoThePreviousCredential() {
        let switched = ContinuousClock.now
        var rows = GatewaySessions.noting([:], session: "s", credential: "new",
                                          status: 200, at: switched)
        rows = GatewaySessions.noting(rows, session: "s", credential: "old",
                                      status: 500, at: switched.advanced(by: .seconds(-30)))

        XCTAssertEqual(rows["s"]?.credential, "new",
                       "a slow request that started before the switch completes after it, and "
                           + "last-writer-wins flipped the row back onto the credential the switch "
                           + "had just left — the invariant this feature exists for")
        XCTAssertEqual(rows["s"]?.lastStatus, 200)
        XCTAssertEqual(rows["s"]?.requests, 2, "the request still counts, only its facts do not win")
    }

    func testATruncatedResponseDoesNotCountASecondRequestForTheSession() {
        let ledger = GatewayLedger()
        ledger.note(path: "/v1/messages", credential: "cc464558", status: 200, session: "s1")
        ledger.noteTruncated(path: "/v1/messages", credential: "cc464558", session: "s1")

        XCTAssertEqual(ledger.sessionRows["s1"]?.requests, 1,
                       "the relay writes the head first and calls note, then reports the truncation "
                           + "through noteTruncated only when the head was already written — one "
                           + "request, two records. The top-level counters already knew this: "
                           + "noteTruncated raises failures and NOT requests, while the per-session "
                           + "row was incremented by both")
        XCTAssertEqual(ledger.sessionRows["s1"]?.lastStatus, 0,
                       "and the truncation still restates what happened to it")
    }

    func testAnOrdinarySecondRequestStillCounts() {
        let ledger = GatewayLedger()
        ledger.note(path: "/v1/messages", credential: "cc464558", status: 200, session: "s1")
        ledger.note(path: "/v1/messages", credential: "cc464558", status: 200, session: "s1")

        XCTAssertEqual(ledger.sessionRows["s1"]?.requests, 2)
    }
}
