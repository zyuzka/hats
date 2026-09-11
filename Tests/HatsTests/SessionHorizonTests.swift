import XCTest
@testable import Hats

final class SessionHorizonTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNoRecordedExpiryFallsBackToTheMechanismAlone() {
        let line = SessionHorizon.line(soonestParkedAccessExpiry: nil, now: now)
        XCTAssertTrue(line.contains("next token renewal"))
        XCTAssertFalse(line.contains("by about"))
    }

    func testAnExpiryInThePastIsNotShownAsAClockTime() {
        let past = now.addingTimeInterval(-120)
        let line = SessionHorizon.line(soonestParkedAccessExpiry: past, now: now)
        XCTAssertTrue(line.contains("due now or overdue"))
        XCTAssertFalse(line.contains("by about"))
    }

    func testAFutureExpiryIsShownAsAClockAndACountdown() {
        let soon = now.addingTimeInterval(25 * 60)
        let line = SessionHorizon.line(soonestParkedAccessExpiry: soon, now: now)
        XCTAssertTrue(line.contains("by about"))
        XCTAssertTrue(line.contains("in 25 min"))
    }

    func testTheClockIsAsciiDigitsRegardlessOfTheDefaultLocale() {
        let soon = now.addingTimeInterval(25 * 60)
        let line = SessionHorizon.line(soonestParkedAccessExpiry: soon, now: now)
        guard let range = line.range(of: #"\d\d:\d\d"#, options: .regularExpression) else {
            return XCTFail("no HH:mm clock found in: \(line)")
        }
        XCTAssertTrue(line[range].allSatisfy { $0.isASCII })
    }

    func testTheCountdownReadsInHoursAndMinutesPastAnHour() {
        XCTAssertEqual(SessionHorizon.minutes(90 * 60), "in 1 h 30 min")
        XCTAssertEqual(SessionHorizon.minutes(120 * 60), "in 2 h")
        XCTAssertEqual(SessionHorizon.minutes(59 * 60), "in 59 min")
        XCTAssertEqual(SessionHorizon.minutes(30), "under a minute")
        XCTAssertEqual(SessionHorizon.minutes(59.9), "under a minute")
        XCTAssertEqual(SessionHorizon.minutes(60), "in 1 min")
    }
}
