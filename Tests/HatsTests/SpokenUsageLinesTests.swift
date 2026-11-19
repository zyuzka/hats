import XCTest
@testable import Hats

final class SpokenUsageLinesTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var resets: Date { now.addingTimeInterval(3600) }

    func testTheFiveHourLineIsSpokenInWords() {
        let reading = UsageReading(session: UsageWindow(used: 41, limit: 100, resetsAt: resets), weekly: nil)

        XCTAssertEqual(HatsCopy.usageLine(reading, timeZone: utc, now: now), "5h: 41% / 09:00")
        XCTAssertEqual(HatsCopy.getUsageSpoken(reading, timeZone: utc, now: now),
                       "5-hour limit 41 percent, resets at 09:00",
                       "VoiceOver reads the shown line sign by sign: \"5 h colon 41 percent slash\"")
        XCTAssertEqual(HatsCopy.getParkedSpoken(reading, rose: 4, timeZone: utc, now: now),
                       "5-hour limit 41 percent, resets at 09:00, up 4 while not being worn")
        XCTAssertNil(HatsCopy.getUsageSpoken(UsageReading(session: nil, weekly: nil), timeZone: utc, now: now))
    }

    func testTheWeekLineIsSpokenInWords() {
        XCTAssertEqual(HatsCopy.getWeekSpoken(percent: 82, resetsAt: resets, isConfirmed: true, timeZone: utc, now: now),
                       "weekly limit 82 percent, resets Fri 15 Jan 09:00")
        XCTAssertEqual(HatsCopy.getWeekSpoken(percent: 82, resetsAt: nil, isConfirmed: false, timeZone: utc, now: now),
                       "weekly limit 82 percent, not confirmed")
        XCTAssertEqual(HatsCopy.getWeekSpoken(percent: 82, resetsAt: now, isConfirmed: true, timeZone: utc, now: now),
                       "weekly limit unknown, last reset Fri 15 Jan 08:00",
                       "the shown line says \"week: ?\" once the reset has passed")
    }

    func testEveryUsageLineOfTheRowCarriesItsSpokenForm() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/HatRowView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        for (shown, spoken) in [
            ("Text(line)", ".accessibilityLabel(HatsCopy.getUsageSpoken(usage) ?? line)"),
            ("Text(parked)", ".accessibilityLabel(HatsCopy.getParkedSpoken(usage, rose: row.roseWhileParked) ?? parked)"),
            ("Text(week)", ".accessibilityLabel(row.weekSpoken ?? week)"),
        ] {
            let at = try XCTUnwrap(text.range(of: shown), "\(shown) is drawn")
            let next = text[at.upperBound...].split(separator: "\n").prefix(2).joined(separator: "\n")
            XCTAssertTrue(next.contains(spoken), "\(shown) is followed by its spoken label")
        }
    }
}
