import XCTest
@testable import Hats

final class CodexUsageHeadersTests: XCTestCase {
    private func reading(_ headers: [String: String]) -> CodexUsageReading? {
        CodexUsageHeaders.reading { headers[$0] }
    }

    func testPlusCarriesFiveHoursAndAWeekMatchedByLength() {
        let plus = reading([
            "x-codex-plan-type": "plus",
            "x-codex-primary-window-minutes": "300",
            "x-codex-primary-used-percent": "7",
            "x-codex-primary-reset-at": "1800000000",
            "x-codex-secondary-window-minutes": "10080",
            "x-codex-secondary-used-percent": "41",
        ])
        XCTAssertEqual(plus?.plan, "plus")
        XCTAssertEqual(plus?.window(minutes: 300)?.percent, 7)
        XCTAssertEqual(plus?.window(minutes: 300)?.resetsAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(plus?.window(minutes: 10080)?.percent, 41)
        XCTAssertEqual(plus?.journalLine, "300m=7%,10080m=41%")
    }

    func testBusinessCarriesOnlyTheWeekInPrimary() {
        let business = reading([
            "x-codex-primary-window-minutes": "10080",
            "x-codex-primary-used-percent": "12",
            "x-codex-secondary-window-minutes": "0",
            "x-codex-secondary-used-percent": "0",
        ])
        XCTAssertEqual(business?.windows, [CodexUsageWindow(minutes: 10080, percent: 12, resetsAt: nil)],
                       "a window of zero minutes is no window, and the week is found by its length")
        XCTAssertNil(business?.window(minutes: 300))
    }

    func testAHugePercentIsHeldAtAHundredInsteadOfStoppingTheApp() {
        let huge = reading([
            "x-codex-primary-window-minutes": "300",
            "x-codex-primary-used-percent": "1e30",
            "x-codex-secondary-window-minutes": "10080",
            "x-codex-secondary-used-percent": "100.4",
        ])
        XCTAssertEqual(huge?.window(minutes: 300)?.percent, 100,
                       "Int(1e30) traps, and the gateway reads this header on every answer")
        XCTAssertEqual(huge?.window(minutes: 10080)?.percent, 100)
        XCTAssertNil(reading(["x-codex-primary-window-minutes": "300", "x-codex-primary-used-percent": "-3"]))
        XCTAssertNil(reading(["x-codex-primary-window-minutes": "300", "x-codex-primary-used-percent": "inf"]))
    }

    func testAnAnswerWithoutUsageHasNoReading() {
        XCTAssertNil(reading(["x-codex-plan-type": "plus"]))
        XCTAssertNil(reading(["x-codex-primary-window-minutes": "300", "x-codex-primary-used-percent": "much"]))
    }
}
