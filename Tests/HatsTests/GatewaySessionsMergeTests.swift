import XCTest
@testable import Hats

final class GatewaySessionsMergeTests: XCTestCase {
    private func table(_ prefix: String, count: Int) -> [String: GatewaySessionRow] {
        var rows: [String: GatewaySessionRow] = [:]
        let base = ContinuousClock.now
        for index in 0..<count {
            let id = "\(prefix)-\(index)"
            rows[id] = GatewaySessionRow(session: id, requests: 1, lastStatus: 200,
                                         lastSeen: base.advanced(by: .seconds(index)),
                                         credential: "cc464558")
        }
        return rows
    }

    func testTwoFullLedgersDoNotMergeIntoTwiceTheCap() {
        let merged = GatewaySessions.merged([
            table("serving", count: GatewaySessions.kept),
            table("retired", count: GatewaySessions.kept),
        ])

        XCTAssertEqual(merged.count, GatewaySessions.kept,
                       "each ledger caps itself, but a port transition holds two of them and the "
                           + "merge used to hand back both in full — up to twice the number the "
                           + "copy beside it promises are the most recent ones kept")
    }

    func testTheMergeKeepsTheMostRecentlySeenRowForASessionInBothLedgers() {
        let older = ContinuousClock.now
        let newer = older.advanced(by: .seconds(30))
        let serving = ["s": GatewaySessionRow(session: "s", requests: 1, lastStatus: 500,
                                              lastSeen: older, credential: "old")]
        let retired = ["s": GatewaySessionRow(session: "s", requests: 1, lastStatus: 200,
                                              lastSeen: newer, credential: "new")]

        let merged = GatewaySessions.merged([serving, retired])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.credential, "new")
    }

    func testTheMergeReportsTheMostRecentlySeenFirst() {
        let base = ContinuousClock.now
        let rows = [
            "a": GatewaySessionRow(session: "a", requests: 1, lastStatus: 200,
                                   lastSeen: base, credential: "c"),
            "b": GatewaySessionRow(session: "b", requests: 1, lastStatus: 200,
                                   lastSeen: base.advanced(by: .seconds(5)), credential: "c"),
        ]

        XCTAssertEqual(GatewaySessions.merged([rows]).map(\.session), ["b", "a"])
    }
}
