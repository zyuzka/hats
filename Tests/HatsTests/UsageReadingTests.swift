import XCTest
@testable import Hats

final class UsageReadingTests: XCTestCase {
    private func payload(fiveHour: [String: Any]?, sevenDay: [String: Any]?) -> [String: Any] {
        var out: [String: Any] = ["seven_day_opus": NSNull(), "extra_usage": ["is_enabled": false]]
        if let fiveHour { out["five_hour"] = fiveHour }
        if let sevenDay { out["seven_day"] = sevenDay }
        return out
    }

    func testAReadingCarriesBothWindowsAsTheUsageEndpointReportsThem() throws {
        let reading = try XCTUnwrap(UsageReading.parsed(payload(
            fiveHour: ["utilization": 26, "resets_at": "2026-08-30T12:50:00.330776+00:00"],
            sevenDay: ["utilization": 22, "resets_at": "2026-09-04T13:00:00.330810+00:00"]
        )))
        XCTAssertEqual(reading.session?.percent, 26)
        XCTAssertEqual(reading.weekly?.percent, 22)
        XCTAssertEqual(reading.session?.resetsAt,
                       UsageReading.date(from: "2026-08-30T12:50:00.330776+00:00"))
        XCTAssertEqual(reading.journalLine, "session=26/100 weekly=22/100")
    }

    func testUtilizationIsAPercentAndMayArriveAsADouble() throws {
        let reading = try XCTUnwrap(UsageReading.parsed(payload(
            fiveHour: ["utilization": 77.6], sevenDay: nil)))
        XCTAssertEqual(reading.session?.percent, 78, "a fractional percent rounds, not truncates")
    }

    func testPercentNeverLeavesZeroToAHundred() {
        XCTAssertEqual(UsageWindow(used: 3, limit: 4, resetsAt: nil).percent, 75)
        XCTAssertEqual(UsageWindow(used: 107, limit: 100, resetsAt: nil).percent, 100,
                       "a provider can report more used than the limit; the meter stops at full")
        XCTAssertEqual(UsageWindow(used: 1, limit: 0, resetsAt: nil).percent, 0,
                       "a zero limit is not a division")
    }

    func testAResetTimeThatCannotBeReadIsAbsentRatherThanWrong() throws {
        let reading = try XCTUnwrap(UsageReading.parsed(payload(
            fiveHour: ["utilization": 1, "resets_at": "tomorrow-ish"], sevenDay: nil)))
        XCTAssertEqual(reading.session?.percent, 1)
        XCTAssertNil(reading.session?.resetsAt)
    }

    func testAWindowWithoutANumberIsNoWindow() throws {
        let reading = try XCTUnwrap(UsageReading.parsed(payload(
            fiveHour: ["utilization": "26"], sevenDay: ["utilization": 22])))
        XCTAssertNil(reading.session, "a string where a number belongs is not a number")
        XCTAssertNotNil(reading.weekly)
    }

    func testAPayloadWithNoUsableWindowIsNoReading() {
        XCTAssertNil(UsageReading.parsed(payload(fiveHour: nil, sevenDay: nil)))
        XCTAssertNil(UsageReading.parsed(["five_hour": NSNull()]))
        XCTAssertNil(UsageReading.parsed([:]))
    }

    func testTheClockIsRenderedInTheGivenZone() throws {
        let date = try XCTUnwrap(UsageReading.date(from: "2026-08-30T18:10:00Z"))
        XCTAssertEqual(UsageReading.clock(date, timeZone: TimeZone(identifier: "UTC")!), "18:10")
        XCTAssertEqual(UsageReading.clock(date, timeZone: TimeZone(identifier: "Europe/Kyiv")!), "21:10")
    }
}
