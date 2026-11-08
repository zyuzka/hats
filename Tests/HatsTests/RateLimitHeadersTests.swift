import XCTest
@testable import Hats

final class RateLimitHeadersTests: XCTestCase {
    private func findReading(_ headers: [String: String]) -> UsageReading? {
        RateLimitHeaders.findReading(in: { headers[$0] })
    }

    private func createWindow(used: Int) -> UsageWindow {
        UsageWindow(
            used: used,
            limit: 100,
            resetsAt: nil
        )
    }

    func testTheHeaderNamesAreTheOnesTheServerWasMeasuredSending() {
        let measured = [
            (RateLimitHeaders.sessionUtilization, "anthropic-ratelimit-unified-5h-utilization"),
            (RateLimitHeaders.sessionReset, "anthropic-ratelimit-unified-5h-reset"),
            (RateLimitHeaders.weeklyUtilization, "anthropic-ratelimit-unified-7d-utilization"),
            (RateLimitHeaders.weeklyReset, "anthropic-ratelimit-unified-7d-reset"),
        ]
        for (name, sent) in measured {
            XCTAssertEqual(
                name,
                sent,
                "a response through the gateway on 07.11 carried exactly this name"
            )
        }
    }

    func testAFractionBecomesAWholePercentOutOfAHundred() throws {
        let read = try XCTUnwrap(findReading([
            RateLimitHeaders.sessionUtilization: "0.26",
            RateLimitHeaders.weeklyUtilization: "0.855",
        ]))

        XCTAssertEqual(read.session, createWindow(used: 26))
        XCTAssertEqual(
            read.weekly,
            createWindow(used: 86),
            "0.855 is 85.5 percent, and half a percent rounds up"
        )
    }

    func testTheResetIsReadAsUnixSeconds() throws {
        let read = try XCTUnwrap(findReading([
            RateLimitHeaders.sessionUtilization: "0.26",
            RateLimitHeaders.sessionReset: "1794106800",
            RateLimitHeaders.weeklyUtilization: "0.51",
            RateLimitHeaders.weeklyReset: "1794574800",
        ]))

        XCTAssertEqual(read.session?.resetsAt, Date(timeIntervalSince1970: 1_794_106_800))
        XCTAssertEqual(read.weekly?.resetsAt, Date(timeIntervalSince1970: 1_794_574_800))
    }

    func testAResetThatIsNotANumberLeavesTheWindowWithoutADate() throws {
        let read = try XCTUnwrap(findReading([
            RateLimitHeaders.sessionUtilization: "0.5",
            RateLimitHeaders.sessionReset: "soon",
        ]))

        XCTAssertEqual(read.session, createWindow(used: 50))
    }

    func testGarbageOrAnEmptyValueIsNoWindowAndNoWindowIsNoSignal() {
        let junk = [
            "abc",
            "",
            " ",
            "nan",
            "0.5%",
        ]
        for value in junk {
            XCTAssertNil(
                findReading([
                    RateLimitHeaders.sessionUtilization: value,
                ]),
                "session value \"\(value)\""
            )
            XCTAssertNil(
                findReading([
                    RateLimitHeaders.weeklyUtilization: value,
                ]),
                "weekly value \"\(value)\""
            )
        }
        XCTAssertNil(findReading([:]), "a response without the headers gives no reading")
        XCTAssertNil(
            findReading([
                RateLimitHeaders.sessionReset: "1794106800",
            ]),
            "a reset with no utilization beside it is not a reading"
        )
    }

    func testAFractionOutsideZeroToOneIsHeldAtTheEdgeInsteadOfTrapping() {
        let rows: [(String, Int)] = [
            ("1e300", 100),
            ("1.05", 100),
            ("-0.5", 0),
            ("-1e300", 0),
        ]
        for (sent, expected) in rows {
            let read = findReading([
                RateLimitHeaders.sessionUtilization: sent,
            ])

            XCTAssertEqual(
                read?.session?.used,
                expected,
                "value \"\(sent)\" is held to 0...100"
            )
        }
    }

    func testOneWindowIsEnoughAndTheOtherStaysEmpty() throws {
        let session = try XCTUnwrap(findReading([
            RateLimitHeaders.sessionUtilization: "0.9",
        ]))
        let weekly = try XCTUnwrap(findReading([
            RateLimitHeaders.sessionUtilization: "abc",
            RateLimitHeaders.weeklyUtilization: "0.98",
        ]))

        XCTAssertEqual(session.session, createWindow(used: 90))
        XCTAssertNil(session.weekly)
        XCTAssertNil(weekly.session, "a broken window next to a good one drops only itself")
        XCTAssertEqual(weekly.weekly, createWindow(used: 98))
    }
}
