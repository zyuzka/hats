import XCTest
@testable import Hats

final class SessionWindowRowsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func window(
        _ session: String,
        percent: Int? = nil,
        tokens: Int? = 100_000,
        state: SessionWindowState = .read,
        title: String? = nil,
        cwd: String? = "/Volumes/work/projects/folder",
        minutesAgo: Double = 1
    ) -> SessionWindow {
        SessionWindow(
            session: session,
            cwd: cwd,
            title: title,
            tokens: state == .compacted ? nil : tokens,
            window: percent == nil ? nil : 1_000_000,
            percent: percent,
            state: state,
            measuredAt: now.addingTimeInterval(-minutesAgo * 60)
        )
    }

    func testTheLabelIsTheTitleElseTheFolderElseTheSession() {
        XCTAssertEqual(HatsCopy.getContextLabel(title: "Fix the login", cwd: "/a/hats", session: "5a32129e-d019"),
                       "Fix the login")
        XCTAssertEqual(HatsCopy.getContextLabel(title: nil, cwd: "/Volumes/work/projects/hats", session: "5a32129e-d019"),
                       "hats")
        XCTAssertEqual(HatsCopy.getContextLabel(title: "   ", cwd: "/a/hats/", session: "5a32129e-d019"), "hats",
                       "a blank title is no title")
        XCTAssertEqual(HatsCopy.getContextLabel(title: nil, cwd: "/", session: "5a32129e-d019"), "5a32129e",
                       "the root folder names nothing")
        XCTAssertEqual(HatsCopy.getContextLabel(title: nil, cwd: nil, session: "5a32129e-d019"), "5a32129e")
        XCTAssertEqual(HatsCopy.getContextLabel(title: "two\nlines", cwd: nil, session: "s"), "two lines",
                       "a title from another program stays on one line")
    }

    func testTheValueIsThePercentElseTheTokensElseCompacted() {
        XCTAssertEqual(HatsCopy.getContextValue(window("s", percent: 45)), "45%")
        XCTAssertEqual(HatsCopy.getContextValue(window("s", tokens: 312_400)), "312k")
        XCTAssertEqual(HatsCopy.getContextValue(window("s", tokens: 312_500)), "313k")
        XCTAssertEqual(HatsCopy.getContextValue(window("s", tokens: 999)), "1k")
        XCTAssertEqual(HatsCopy.getContextValue(window("s", tokens: Int.max)), "\(Int.max / 1000 + 1)k",
                       "no overflow on a count from another program")
        XCTAssertEqual(HatsCopy.getContextValue(window("s", state: .compacted)), "compacted")
        XCTAssertEqual(HatsCopy.contextHeader, "Context")
    }

    func testTheMenuShowsTheLastHourLargestPercentFirstAndAtMostFive() {
        let windows = [
            window("low", percent: 12),
            window("unknown", tokens: 312_000),
            window("compacted", state: .compacted),
            window("high", percent: 70),
            window("middle", percent: 45),
            window("stale", percent: 99, minutesAgo: 61),
            window("next", percent: 30),
            window("edge", percent: 20, minutesAgo: 60),
        ]

        let rows = SessionWindow.getMenuRows(windows, now: now)

        XCTAssertEqual(rows.map(\.id), ["high", "middle", "next", "edge", "low"])
        XCTAssertEqual(rows.first?.value, "70%")
        XCTAssertEqual(rows.first?.label, "folder · high", "every row here shares one folder, so each is told apart")
    }

    func testSessionsWithoutAPercentGoBelowAndTheNewestFirst() {
        let windows = [
            window("unknown-older", tokens: 312_000, minutesAgo: 30),
            window("compacted", state: .compacted, minutesAgo: 5),
            window("measured", percent: 3),
        ]

        let rows = SessionWindow.getMenuRows(windows, now: now)

        XCTAssertEqual(rows.map(\.id), ["measured", "compacted", "unknown-older"])
        XCTAssertEqual(rows.map(\.value), ["3%", "compacted", "312k"])
    }

    func testAMeasurementUpToAnHourAheadIsShownAndBeyondItIsNot() {
        let windows = [
            window("ahead-sixty", percent: 40, minutesAgo: -60),
            window("ahead-sixty-one", percent: 90, minutesAgo: -61),
        ]

        let rows = SessionWindow.getMenuRows(windows, now: now)

        XCTAssertEqual(rows.map(\.id), ["ahead-sixty"], "a clock ahead by more than an hour is not this hour")
    }

    func testRepeatedLabelsCarryTheStartOfTheirSession() {
        let windows = [
            window("5a32129e-d019", percent: 50, cwd: "/Volumes/work/projects/hats"),
            window("77c1e0aa-0001", percent: 40, cwd: "/Volumes/other/hats"),
            window("9f00bb11-0002", percent: 30, cwd: "/Volumes/work/projects/notes"),
            window("1234abcd-0003", percent: 20, title: "hats"),
        ]

        let rows = SessionWindow.getMenuRows(windows, now: now)

        XCTAssertEqual(rows.map(\.label), ["hats · 5a32", "hats · 77c1", "notes", "hats · 1234"],
                       "two sessions in folders named alike, and a title equal to them, are told apart")
        XCTAssertEqual(HatsCopy.getContextLabel("hats", telling: "5a32129e-d019"), "hats · 5a32")
    }

    func testNoRecentSessionMeansNoBlock() {
        XCTAssertEqual(SessionWindow.getMenuRows([window("stale", percent: 50, minutesAgo: 90)], now: now), [])
        XCTAssertEqual(SessionWindow.getMenuRows([], now: now), [])
        XCTAssertTrue(HatsSnapshot().contextRows.isEmpty, "a fresh snapshot shows no Context block")
    }
}
