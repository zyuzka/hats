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
                       "5-hour limit 41 percent, resets at 09:00, up 4 percent while not being worn")
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

    func testTheRowCarriesTheSpokenWeekBesideTheShownOne() {
        let sighting = WeekSighting(window: UsageWindow(used: 82, limit: 100, resetsAt: resets), isConfirmed: false)
        let hat = Account(id: "work", email: "work@x.co", browser: nil)

        let row = HatRowState(hat: hat, isWearing: true, usage: nil, usageTrouble: nil, week: sighting,
                              now: now, timeZone: utc)

        XCTAssertEqual(row.week, "week: 82%? / Fri 15 Jan 09:00")
        XCTAssertEqual(row.weekSpoken, "weekly limit 82 percent, not confirmed, resets Fri 15 Jan 09:00",
                       "the row gives the label from the same sighting, zone and moment as the shown line")
        XCTAssertNil(HatRowState(hat: hat, isWearing: true, usage: nil, usageTrouble: nil, now: now).weekSpoken,
                     "no week sighted, nothing to speak")
    }

    func testEveryUsageLineOfTheRowCarriesItsSpokenForm() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let read = { (name: String) in
            try String(contentsOf: root.appendingPathComponent("Sources/Hats/\(name)"), encoding: .utf8)
        }
        let view = try read("HatRowView.swift")
        let lines = try read("UsageBars.swift")

        XCTAssertTrue(view.contains("case .text(let text, let spoken):\n"
                                        + "                Text(text).font(.system(size: 11)).foregroundStyle(secondary)\n"
                                        + "                    .accessibilityLabel(spoken ?? text)"),
                      "every text line of the row is drawn with its spoken label")
        for spoken in [
            "HatsCopy.getUsageSpoken(usage, timeZone: timeZone, now: now)",
            "HatsCopy.getParkedSpoken(usage, rose: rose, timeZone: timeZone, now: now)",
            "row.week.map { [.text($0, spoken: row.weekSpoken)] }",
        ] {
            XCTAssertTrue(lines.contains(spoken), "the percent lines carry \(spoken)")
        }
    }
}
