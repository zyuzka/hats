import XCTest
@testable import Hats

final class MeterReadingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let reading = UsageReading(session: nil, weekly: nil)

    func testNoReadingIsUnavailableUnlessThePollSaidWhy() {
        XCTAssertEqual(MeterReading.of(nil, readAt: now, trouble: nil, now: now), .unavailable)
        XCTAssertEqual(MeterReading.of(reading, readAt: nil, trouble: nil, now: now), .unavailable)
        XCTAssertEqual(MeterReading.unavailable.line, "unavailable")
        XCTAssertEqual(MeterReading.unavailable.age, "-")
        let refused = MeterReading.of(nil, readAt: nil, trouble: .fetchFailed("refused 401"), now: now)
        XCTAssertEqual(refused.line, "refused 401", "a token the endpoint rejects reads differently from a meter nobody polled")
        XCTAssertNil(refused.trouble, "the line already carries it")
    }

    func testAReadingCarriesItsLineItsOwnAgeAndTheLatestTrouble() {
        let meters = MeterReading.of(reading, readAt: now.addingTimeInterval(-125), trouble: .fetchFailed("unreachable"), now: now)
        XCTAssertEqual(meters.line, reading.journalLine)
        XCTAssertEqual(meters.age, "125s", "the age is this hat's own, not the poll's")
        XCTAssertEqual(meters.trouble, "unreachable", "a kept number and a failed latest poll are both said")
    }
}
