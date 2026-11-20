import XCTest
@testable import Hats

final class ProviderSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func row(
        _ id: String,
        session: Int? = nil,
        sessionResetsAt: Date? = nil,
        week: Int? = nil,
        weekResetsAt: Date? = nil,
        onVacation: Bool = false,
        tool: Tool = .claudeCode
    ) -> HatRowState {
        var hat = Account(id: id, email: "\(id)@company.com", browser: nil)
        hat.tool = tool
        if onVacation { hat.vacationSince = now }
        let later = now.addingTimeInterval(3600)
        let sessionWindow = session.map { UsageWindow(used: $0, limit: 100, resetsAt: sessionResetsAt ?? later) }
        let weekWindow = week.map { UsageWindow(used: $0, limit: 100, resetsAt: weekResetsAt ?? later) }
        let reading = sessionWindow == nil && weekWindow == nil
            ? nil
            : UsageReading(session: sessionWindow, weekly: weekWindow)

        return HatRowState(
            hat: hat,
            isWearing: false,
            usage: reading,
            usageTrouble: nil,
            week: weekWindow.map { WeekSighting(window: $0, isConfirmed: true) },
            now: now
        )
    }

    private func line(_ rows: [HatRowState]) -> String {
        HatsCopy.providerAverage(ProviderSummary.of(rows, now: now))
    }

    func testCAP7AveragesRoundToTheNearestWhole() {
        let rows = [row("a", session: 11, week: 90), row("b", session: 70, week: 91), row("c", session: 39, week: 99)]

        XCTAssertEqual(line(rows), "5h 40% · week 93%")
    }

    func testAHalfRoundsUp() {
        XCTAssertEqual(ProviderAverage.rounded([10, 11]), 11)
        XCTAssertEqual(ProviderAverage.rounded([10, 10, 11]), 10)
        XCTAssertEqual(ProviderAverage.rounded([0, 1]), 1)
        XCTAssertNil(ProviderAverage.rounded([]))
    }

    func testAHatOnVacationCountsOnlyInTheBrackets() {
        let rows = [row("a", session: 10, week: 20), row("b", session: 30, week: 40, onVacation: true)]

        XCTAssertEqual(line(rows), "5h 10% (20%) · week 20% (30%)")
    }

    func testABusinessHatWithoutAFiveHourWindowCountsOnlyInTheWeek() {
        let rows = [row("plus", session: 10, week: 20, tool: .codex), row("business", week: 60, tool: .codex)]

        XCTAssertEqual(line(rows), "5h 10% · week 40%")
    }

    func testEveryHatOnVacationLeavesADashBeforeTheBrackets() {
        XCTAssertEqual(line([row("a", session: 50, week: 70, onVacation: true)]), "5h – (50%) · week – (70%)")
    }

    func testHatsWithoutAReadingGiveDashes() {
        XCTAssertEqual(line([row("a"), row("b")]), "5h – · week –")
        XCTAssertEqual(line([]), "5h – · week –")
    }

    func testAHatWithoutAReadingStaysOutOfTheAverage() {
        XCTAssertEqual(line([row("a", session: 30, week: 50), row("b")]), "5h 30% · week 50%")
    }

    func testAWindowWhoseResetHasPassedCountsAsZero() {
        let rows = [row("a", session: 20, week: 80, weekResetsAt: now.addingTimeInterval(-60)), row("b", session: 40, week: 40)]

        XCTAssertEqual(line(rows), "5h 30% · week 20%")
    }

    func testAFiveHourWindowWhoseResetHasPassedCountsAsZero() {
        let past = now.addingTimeInterval(-60)
        let rows = [row("a", session: 80, sessionResetsAt: past, week: 30), row("b", session: 40, week: 50)]

        XCTAssertEqual(line(rows), "5h 20% · week 40%")
    }

    func testTheBracketsShowOnlyOnAWindowAVacationHatEntered() {
        let rows = [row("a", session: 10, week: 20), row("b", week: 40, onVacation: true)]

        XCTAssertEqual(line(rows), "5h 10% · week 20% (30%)")
    }
}
