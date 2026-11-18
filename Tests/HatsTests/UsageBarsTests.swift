import XCTest
@testable import Hats

final class UsageBarsTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC") ?? .current
    private let now = Date(timeIntervalSince1970: 1_794_909_600)

    private func at(_ text: String) -> Date {
        UsageReading.date(from: text) ?? Date.distantPast
    }

    private func hat(_ id: String) -> Account {
        Account(id: id, email: "\(id)@company.com", browser: nil)
    }

    private func window(_ percent: Int, resets: String?) -> UsageWindow {
        UsageWindow(used: percent, limit: 100, resetsAt: resets.map(at))
    }

    private func row(
        wearing: Bool = true,
        session: UsageWindow? = nil,
        weekly: UsageWindow? = nil,
        trouble: UsageTrouble? = nil,
        rose: Int? = nil,
        week: WeekSighting? = nil,
        noUsage: Bool = false
    ) -> HatRowState {
        let usage = noUsage ? nil : UsageReading(session: session, weekly: weekly)
        return HatRowState(
            hat: hat("work"),
            isWearing: wearing,
            usage: usage,
            usageTrouble: trouble,
            roseWhileParked: rose,
            week: week,
            now: now,
            timeZone: utc
        )
    }

    private func lines(_ row: HatRowState, _ display: UsageDisplay, handover: String? = nil) -> [RowDetailLine] {
        RowDetail.lines(of: row, display: display, handover: handover, timeZone: utc, now: now)
    }

    private var weekNinety: WeekSighting {
        WeekSighting(window: window(90, resets: "2026-11-23T10:00:00Z"), isConfirmed: true)
    }

    private var sessionEleven: UsageWindow { window(11, resets: "2026-11-17T14:05:00Z") }

    func testTheClockOfTheseTestsIsATuesdayMorning() {
        XCTAssertEqual(UsageReading.dayAndClock(now, timeZone: utc), "Tue 17 Nov 10:00")
    }

    func testPercentOnAWornHatIsTheTextAsBefore() {
        let worn = row(session: sessionEleven, week: weekNinety)
        XCTAssertEqual(lines(worn, .percent, handover: "next: personal"), [
            .text("5h: 11% / 14:05"),
            .text("week: 90% / Mon 23 Nov 10:00"),
            .text("next: personal"),
        ])
    }

    func testBarsOnAWornHatAreTwoLabelledBarsWithTheirResetTimesAndNoPercentText() {
        let worn = row(session: sessionEleven, week: weekNinety)
        XCTAssertEqual(lines(worn, .bars, handover: "next: personal"), [
            .bar(UsageBar(label: "5h", percent: 11, tone: .neutral, fill: .solid, resets: "14:05")),
            .bar(UsageBar(label: "week", percent: 90, tone: .critical, fill: .solid, resets: "Mon 23 Nov 10:00")),
            .text("next: personal"),
        ])
        for line in lines(worn, .bars) {
            if case .text(let text) = line { XCTAssertFalse(text.contains("%"), text) }
        }
    }

    func testTheToneFollowsTheFillAtSeventyAndNinetyOnly() {
        XCTAssertEqual(UsageBarTone.of(percent: 69), .neutral)
        XCTAssertEqual(UsageBarTone.of(percent: 70), .warning)
        XCTAssertEqual(UsageBarTone.of(percent: 89), .warning)
        XCTAssertEqual(UsageBarTone.of(percent: 90), .critical)
        for (percent, tone) in [(69, UsageBarTone.neutral), (70, .warning), (89, .warning), (90, .critical)] {
            let worn = row(session: window(percent, resets: nil))
            XCTAssertEqual(lines(worn, .bars).first, .bar(UsageBar(
                label: "5h",
                percent: percent,
                tone: tone,
                fill: .solid,
                resets: nil
            )))
        }
    }

    func testAnUnconfirmedWeekIsAFaintBar() {
        let sighting = WeekSighting(window: window(90, resets: "2026-11-23T10:00:00Z"), isConfirmed: false)
        XCTAssertEqual(lines(row(week: sighting, noUsage: true), .bars), [
            .bar(UsageBar(label: "week", percent: 90, tone: .critical, fill: .faint, resets: "Mon 23 Nov 10:00")),
        ])
    }

    func testABarWithoutAResetTimeHasNoTime() {
        let sighting = WeekSighting(window: window(40, resets: nil), isConfirmed: true)
        let worn = row(session: window(20, resets: nil), week: sighting)
        XCTAssertEqual(lines(worn, .bars), [
            .bar(UsageBar(label: "5h", percent: 20, tone: .neutral, fill: .solid, resets: nil)),
            .bar(UsageBar(label: "week", percent: 40, tone: .neutral, fill: .solid, resets: nil)),
        ])
    }

    func testAWeekThatHasAlreadyResetIsADashedEmptyBarWithItsResetTime() {
        for resets in ["2026-11-17T09:00:00Z", "2026-11-17T10:00:00Z"] {
            for confirmed in [true, false] {
                let sighting = WeekSighting(window: window(90, resets: resets), isConfirmed: confirmed)
                let worn = row(session: sessionEleven, week: sighting)
                XCTAssertEqual(lines(worn, .bars).last, .bar(UsageBar(
                    label: "week",
                    percent: 0,
                    tone: .neutral,
                    fill: .emptyDashed,
                    resets: UsageReading.dayAndClock(at(resets), timeZone: utc)
                )), "\(resets) confirmed=\(confirmed)")
                XCTAssertEqual(lines(worn, .percent).last,
                               .text("week: ? / \(UsageReading.dayAndClock(at(resets), timeZone: utc))"))
            }
        }
    }

    func testFiveHoursThatHaveAlreadyResetKeepTheEarlierPercentWithoutATime() {
        for resets in ["2026-11-17T09:00:00Z", "2026-11-17T10:00:00Z"] {
            let worn = row(session: window(64, resets: resets))
            XCTAssertEqual(lines(worn, .bars),
                           [.bar(UsageBar(label: "5h", percent: 64, tone: .neutral, fill: .solid, resets: nil))])
            XCTAssertEqual(lines(worn, .percent), [.text("5h: 64%")])
        }
    }

    func testWithoutAFiveHourWindowThereIsOnlyTheWeekBar() {
        let worn = row(weekly: weekNinety.window, week: weekNinety)
        XCTAssertEqual(lines(worn, .bars), [
            .bar(UsageBar(label: "week", percent: 90, tone: .critical, fill: .solid, resets: "Mon 23 Nov 10:00")),
        ])
    }

    func testAFailedCheckKeepsTheEarlierReadingAsBarsAndSaysSo() {
        for trouble in [UsageTrouble.fetchFailed("unreachable"), .renewalFailed("http 500")] {
            for wearing in [true, false] {
                let hat = row(wearing: wearing, session: sessionEleven, trouble: trouble, week: weekNinety)
                XCTAssertEqual(lines(hat, .bars), [
                    .bar(UsageBar(label: "5h", percent: 11, tone: .neutral, fill: .solid, resets: "14:05")),
                    .bar(UsageBar(label: "week", percent: 90, tone: .critical, fill: .solid,
                                  resets: "Mon 23 Nov 10:00")),
                    .text("latest check failed — \(trouble.journalLine)"),
                ], "\(trouble) wearing=\(wearing)")
            }
        }
    }

    func testUnknownUsageWithARememberedWeekSaysSoAndShowsAFaintWeek() {
        let sighting = WeekSighting(window: window(30, resets: "2026-11-23T10:00:00Z"), isConfirmed: false)
        for wearing in [true, false] {
            let hat = row(wearing: wearing, trouble: .tokenExpired, week: sighting, noUsage: true)
            XCTAssertEqual(lines(hat, .bars), [
                .text(UsageTrouble.tokenExpired.onTheRow),
                .bar(UsageBar(label: "week", percent: 30, tone: .neutral, fill: .faint, resets: "Mon 23 Nov 10:00")),
            ])
        }
    }

    func testUnknownUsageWithNothingRememberedIsOnlyTheSentence() {
        let hat = row(trouble: .nothingStored, noUsage: true)
        XCTAssertEqual(lines(hat, .bars), [.text(UsageTrouble.nothingStored.onTheRow)])
    }

    func testAParkedHatShowsTheSameBarsAndDropsTheRiseWhileParked() {
        let parked = row(wearing: false, session: sessionEleven, rose: 5, week: weekNinety)
        XCTAssertEqual(lines(parked, .bars), [
            .bar(UsageBar(label: "5h", percent: 11, tone: .neutral, fill: .solid, resets: "14:05")),
            .bar(UsageBar(label: "week", percent: 90, tone: .critical, fill: .solid, resets: "Mon 23 Nov 10:00")),
        ])
        XCTAssertEqual(lines(parked, .percent), [
            .text("5h: 11% / 14:05 · up 5 while not being worn"),
            .text("week: 90% / Mon 23 Nov 10:00"),
        ])
    }

    func testPercentKeepsItsExactTextOnTheBranchesWithoutANumberLine() {
        let failed = row(trouble: .fetchFailed("unreachable"), week: weekNinety, noUsage: true)
        XCTAssertEqual(lines(failed, .percent, handover: "next: personal"), [
            .text("limits unknown — unreachable"),
            .text("week: 90% / Mon 23 Nov 10:00"),
        ])
        let weekOnly = row(wearing: false, week: weekNinety, noUsage: true)
        XCTAssertEqual(lines(weekOnly, .percent), [.text("week: 90% / Mon 23 Nov 10:00")])
        let nothing = row(wearing: false, noUsage: true)
        XCTAssertEqual(lines(nothing, .percent), [])
    }

    func testTheWornHatGetsTheMarkAndAParkedHatNone() {
        XCTAssertEqual(RowMark.of(row(wearing: true), tool: .claudeCode), .hat(.claudeCode))
        XCTAssertEqual(RowMark.of(row(wearing: false), tool: .claudeCode), .blank)
    }

    func testTheBarsTurnOrangeAtTheSameSeventyAsTheMenuBarMeter() {
        XCTAssertEqual(UsageBarTone.warningFrom, Mark.meterFrom)
    }

    private func source(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(name)

        return try String(contentsOf: url, encoding: .utf8)
    }

    func testAChoiceIsStoredSavedAndRedrawnAndTheListPassesItToEveryRow() throws {
        let menu = try source("Sources/Hats/AppDelegate+Menu.swift")
        let list = try source("Sources/Hats/HatListView.swift")
        let row = try source("Sources/Hats/HatRowView.swift")

        XCTAssertTrue(menu.contains(
            "guard settings.usageDisplay != display else { return }\n"
                + "        settings.usageDisplay = display\n        saveSettings()\n        redraw()"
        ))
        XCTAssertTrue(list.contains("display: snapshot.settings.usageDisplay,\n                    tool: row.tool,"))
        XCTAssertTrue(row.contains("switch RowMark.of(row, tool: tool) {"))
        XCTAssertTrue(row.contains("UsageBarView(bar: bar, secondary: secondary, lit: lit)"))
    }
}
