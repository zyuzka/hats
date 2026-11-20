import UserNotifications
import XCTest
@testable import Hats

final class LimitThresholdNoticesTests: XCTestCase {
    private var root: URL!
    private var told: [UNMutableNotificationContent] = []
    private var lines: [(String, [String: String])] = []
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private let launch = Date(timeIntervalSince1970: 1_800_000_000.250)
    private let resets = Date(timeIntervalSince1970: 1_800_010_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("limit-notices-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func createNotices(launchedAt: Date? = nil) -> LimitThresholdNotices {
        let notices = LimitThresholdNotices(
            root: root,
            launchedAt: launchedAt ?? launch,
            notify: { [unowned self] in told.append($0) },
            log: { [unowned self] event, details in lines.append((event, details)) },
            now: { [unowned self] in clock }
        )
        notices.hatTitle = { $0 == "work" ? "Work" : $0 }

        return notices
    }

    private func event(
        _ stage: LimitStage,
        after seconds: TimeInterval = 60,
        percent: Double = 72.5,
        worn: String = "work",
        reason: LimitReason = .noHat
    ) -> LimitEvent {
        LimitEvent(stage: stage, at: launch.addingTimeInterval(seconds), percent: percent, worn: worn, reason: reason)
    }

    private func episode(
        _ events: [LimitEvent],
        limit: StageLimit = .fiveHour,
        resetsAt: Date? = nil,
        save: Int? = 80
    ) -> LimitEpisode {
        LimitEpisode(
            limit: limit,
            resetsAt: resetsAt ?? resets,
            percent: 81.5,
            warnPercent: 70,
            savePercent: save,
            events: events
        )
    }

    private func read(_ sessions: [String: [LimitEpisode]]) -> SessionStagesRead {
        let stages = sessions.keys.sorted().map { session in
            SessionStage(
                session: session,
                cwd: nil,
                kind: nil,
                warnRound: 0,
                saveRound: 0,
                percent: nil,
                warnPercent: nil,
                savePercent: nil,
                at: launch,
                drainMinutes: nil,
                limitEpisodes: sessions[session] ?? [],
                limitTrouble: nil
            )
        }

        return SessionStagesRead(stages: stages, listed: Set(sessions.keys))
    }

    private func windowStage(_ session: String, kind: SessionStageKind?) -> SessionStage {
        SessionStage(
            session: session,
            cwd: nil,
            kind: kind,
            warnRound: 1,
            saveRound: 1,
            percent: 81,
            warnPercent: 60,
            savePercent: 70,
            at: launch,
            drainMinutes: nil,
            limitEpisodes: [],
            limitTrouble: nil
        )
    }

    private var titles: [String] { told.map(\.title) }
    private var bodies: [String] { told.map(\.body) }

    func testOneNoticePerHatLimitEpisodeAndStageWithItsTitleBodyAndJournalLine() {
        let notices = createNotices()
        let one = read(["a": [episode([event(.warned)])]])

        notices.noteARead(one)
        notices.noteARead(one)

        XCTAssertEqual(titles, ["Work — 5-hour 72%"], "the hat's title, the limit word and the percent floored")
        XCTAssertEqual(bodies, ["No other hat to switch to. Sessions anchor at 80%."])
        let alerts = lines.filter { $0.0 == "limit.alert" }.map(\.1)
        XCTAssertEqual(alerts, [
            [
                "hat": "work",
                "limit": "five_hour",
                "stage": "warned",
                "percent": "72",
                "episode": ISO8601DateFormatter().string(from: resets),
                "at": "2027-01-15T08:01:00.250Z",
                "early": "0",
            ],
        ])
    }

    private func earlyEvent(after seconds: TimeInterval = 60, percent: Double = 58) -> LimitEvent {
        LimitEvent(
            stage: .warned,
            at: launch.addingTimeInterval(seconds),
            percent: percent,
            worn: "work",
            reason: .noHat,
            early: true,
            minutesToSave: 11,
            target: 80,
            leadSeconds: 682
        )
    }

    private var alerts: [[String: String]] { lines.filter { $0.0 == "limit.alert" }.map(\.1) }

    func testAnEarlySignalIsToldInsteadOfTheUsualWarningWithItsPaceInTheJournal() {
        let notices = createNotices()
        var usual = event(.warned, after: 300, percent: 72)
        usual.target = 80
        usual.leadSeconds = 682

        notices.noteARead(read(["a": [episode([earlyEvent()])]]))
        notices.noteARead(read(["b": [episode([usual])]]))

        XCTAssertEqual(titles, ["Work — 5-hour 58%"])
        XCTAssertEqual(bodies, ["Spending fast: 80% in about 11 min. No other hat to switch to."])
        XCTAssertEqual(alerts, [
            [
                "hat": "work",
                "limit": "five_hour",
                "stage": "warned",
                "percent": "58",
                "episode": ISO8601DateFormatter().string(from: resets),
                "at": "2027-01-15T08:01:00.250Z",
                "early": "1",
                "target": "80",
                "lead_seconds": "682",
                "minutes_to_save": "11",
            ],
        ])
    }

    func testTheAnchorLineOfAnEpisodeCarriesTheEpisodeOfItsWarningAndNoMinutes() {
        let notices = createNotices()
        var asked = event(.asked, after: 600, percent: 81)
        asked.target = 80
        asked.leadSeconds = 682

        notices.noteARead(read(["a": [episode([earlyEvent()])]]))
        notices.noteARead(read(["b": [episode([asked], resetsAt: resets.addingTimeInterval(120))]]))

        XCTAssertEqual(alerts.map { $0["episode"] }, [
            ISO8601DateFormatter().string(from: resets),
            ISO8601DateFormatter().string(from: resets),
        ])
        XCTAssertEqual(alerts.map { $0["early"] }, ["1", "0"])
        XCTAssertEqual(alerts.map { $0["target"] }, ["80", "80"])
        XCTAssertEqual(alerts.map { $0["lead_seconds"] }, ["682", "682"])
        XCTAssertEqual(alerts.map { $0["minutes_to_save"] }, ["11", nil])
    }

    func testAnEarlySignalToldBeforeARestartIsNotToldOrJournaledAgain() {
        let first = createNotices()
        first.noteARead(read(["a": [episode([earlyEvent()])]]))

        createNotices().noteARead(read(["a": [episode([earlyEvent()])]]))

        XCTAssertEqual(told.count, 1)
        XCTAssertEqual(alerts.count, 1)
    }

    func testAnEarlyEventWithoutItsMinutesFallsBackToTheUsualBody() {
        let notices = createNotices()
        var partial = earlyEvent()
        partial.minutesToSave = nil

        notices.noteARead(read(["a": [episode([partial])]]))

        XCTAssertEqual(bodies, ["No other hat to switch to. Sessions anchor at 80%."])
    }

    func testAnEarlyEventWithoutItsTargetIsJournaledAsTheUsualWarningLikeItsBody() {
        let notices = createNotices()
        var partial = earlyEvent()
        partial.target = nil

        notices.noteARead(read(["a": [episode([partial])]]))

        XCTAssertEqual(bodies, ["No other hat to switch to. Sessions anchor at 80%."])
        XCTAssertEqual(alerts.map { $0["early"] }, ["0"])
        XCTAssertEqual(alerts.map { $0["minutes_to_save"] }, [nil])
    }

    func testAWarningBeforeARestartAndAnAnchorAfterItShareTheEpisodeInTheJournal() {
        createNotices().noteARead(read(["a": [episode([earlyEvent()])]]))
        var asked = event(.asked, after: 600, percent: 81)
        asked.target = 80

        createNotices().noteARead(read(["b": [episode([asked], resetsAt: resets.addingTimeInterval(120))]]))

        XCTAssertEqual(alerts.map(\.["stage"]), ["warned", "asked"])
        XCTAssertEqual(alerts.map { $0["episode"] }, [
            ISO8601DateFormatter().string(from: resets),
            ISO8601DateFormatter().string(from: resets),
        ])
    }

    func testAWeeklyEarlySignalIsTitledWithTheWeeklyLimit() {
        let notices = createNotices()

        notices.noteARead(read(["a": [episode([earlyEvent()], limit: .sevenDay)]]))

        XCTAssertEqual(titles, ["Work — weekly 58%"])
        XCTAssertEqual(bodies, ["Spending fast: 80% in about 11 min. No other hat to switch to."])
        XCTAssertEqual(alerts.map { $0["limit"] }, ["seven_day"])
    }

    func testBothLimitsSignalledEarlyAtOnceAreTwoNotices() {
        let notices = createNotices()

        notices.noteARead(read(["a": [episode([earlyEvent()]), episode([earlyEvent()], limit: .sevenDay)]]))

        XCTAssertEqual(Set(titles), ["Work — 5-hour 58%", "Work — weekly 58%"])
        XCTAssertEqual(alerts.map { $0["early"] }, ["1", "1"])
    }

    func testWarnedAndAskedSeenInOneReadAreTwoNoticesInThatOrder() {
        let notices = createNotices()

        notices.noteARead(read(["a": [episode([event(.asked, after: 120, percent: 81.5), event(.warned)])]]))

        XCTAssertEqual(titles, ["Work — 5-hour 72%", "Work — 5-hour 81%"])
        XCTAssertEqual(bodies, [
            "No other hat to switch to. Sessions anchor at 80%.",
            "No other hat to switch to. Sessions anchor at the end of their turn.",
        ])
    }

    func testTwoSessionsWritingEventsOfOneEpisodeAreOneNotice() {
        let notices = createNotices()

        notices.noteARead(read([
            "a": [episode([event(.warned, after: 60)])],
            "b": [episode([event(.warned, after: 90, percent: 75)], resetsAt: resets.addingTimeInterval(120))],
        ]))

        XCTAssertEqual(titles, ["Work — 5-hour 72%"])
    }

    func testAnEventAlreadyToldBeforeARestartIsNotToldAgain() {
        let first = createNotices()
        first.noteARead(read(["a": [episode([event(.warned)])]]))
        XCTAssertEqual(told.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(LimitNoticesFile.name).path), "the memory lives in limit-notices.json")

        let restarted = createNotices(launchedAt: launch)
        restarted.noteARead(read(["a": [episode([event(.warned)])]]))

        XCTAssertEqual(told.count, 1, "\(titles)")
    }

    func testAnEventBeforeTheLaunchIsNotToldAndOneAtTheSameMillisecondIs() {
        let notices = createNotices()

        notices.noteARead(read(["a": [episode([event(.warned, after: -0.001)])]]))
        XCTAssertEqual(told.count, 0, "one millisecond before the launch")
        notices.noteARead(read(["a": [episode([event(.warned, after: 0.0004)])]]))

        XCTAssertEqual(told.count, 1, "the launch at .250 and the event at .2504 share the millisecond")
    }

    func testAnHourBetweenTheResetTimesIsANewEpisodeAndLessIsTheSame() {
        let notices = createNotices()
        notices.noteARead(read(["a": [episode([event(.warned)])]]))

        notices.noteARead(read(["b": [episode([event(.warned, after: 70)], resetsAt: resets.addingTimeInterval(-3599))]]))
        XCTAssertEqual(told.count, 1, "59 min 59 s earlier is the same episode")
        notices.noteARead(read(["c": [episode([event(.warned, after: 80)], resetsAt: resets.addingTimeInterval(3600))]]))
        XCTAssertEqual(told.count, 2, "exactly an hour later is a new episode")
        notices.noteARead(read(["d": [episode([event(.warned, after: 90)], resetsAt: resets.addingTimeInterval(-3600))]]))

        XCTAssertEqual(told.count, 3, "exactly an hour earlier is a new episode too")
    }

    func testAnotherHatAnotherLimitAndAnotherStageAreEachTheirOwnNotice() {
        let notices = createNotices()

        notices.noteARead(read(["a": [
            episode([event(.warned)]),
            episode([event(.warned, after: 61, worn: "personal")]),
            episode([event(.warned, after: 62)], limit: .sevenDay),
            episode([event(.asked, after: 63)]),
        ]]))

        XCTAssertEqual(titles, ["Work — 5-hour 72%", "personal — 5-hour 72%", "Work — weekly 72%", "Work — 5-hour 72%"])
    }

    func testThePreviousEpisodeIsToldBesideTheCurrentOne() {
        let notices = createNotices()

        notices.noteARead(read(["a": [
            episode([event(.asked, after: 60, percent: 90)], resetsAt: resets.addingTimeInterval(-18000)),
            episode([event(.warned, after: 120)]),
        ]]))

        XCTAssertEqual(titles, ["Work — 5-hour 90%", "Work — 5-hour 72%"])
    }

    func testEntriesAreKeptEightDays() throws {
        let notices = createNotices()
        notices.noteARead(read(["a": [episode([event(.warned)])]]))

        clock = clock.addingTimeInterval(8 * 86400 - 1)
        notices.noteARead(read(["b": [episode([event(.warned, after: 90)])]]))
        XCTAssertEqual(told.count, 1, "kept on the eighth day")
        clock = clock.addingTimeInterval(2)
        notices.noteARead(read(["b": [episode([event(.warned, after: 90)])]]))
        XCTAssertEqual(told.count, 1, "the record lives on while an event of its episode is younger than eight days")
        clock = clock.addingTimeInterval(120)
        notices.noteARead(read(["b": [episode([event(.warned, after: 90)])]]))

        XCTAssertEqual(told.count, 1, "the record is forgotten after eight days, and the event, as old, is not told again")
        XCTAssertEqual(LimitNoticesFile(root: root, log: { _, _ in }).getEntries(), [], "the record was pruned")
    }

    func testALaterEventOfTheSameEpisodeKeepsTheRecordPastEightDaysFromTheFirst() throws {
        let notices = createNotices()
        let first = episode([event(.warned)])
        let later = episode([event(.warned, after: 3 * 86400)])
        notices.noteARead(read(["a": [first]]))
        clock = clock.addingTimeInterval(3 * 86400 + 60)
        notices.noteARead(read(["a": [first], "b": [later]]))

        clock = clock.addingTimeInterval(5 * 86400 + 60)
        notices.noteARead(read(["a": [first], "b": [later]]))

        XCTAssertEqual(told.count, 1, "the second session's event, three days younger, is the same episode")
    }

    func testAnEventStillInAStageFileAfterEightDaysOfRunningIsNotToldAgain() throws {
        let notices = createNotices()
        let stillThere = read(["a": [episode([event(.warned)])]])
        notices.noteARead(stillThere)

        clock = clock.addingTimeInterval(8 * 86400 + 120)
        notices.noteARead(stillThere)
        notices.noteARead(stillThere)

        XCTAssertEqual(told.count, 1, "the same event, after launch and past the kept period, comes once")
    }

    func testTheReasonsAndTheBodiesOfEachStage() {
        XCTAssertEqual(LimitReason.allCases.map(HatsCopy.getLimitReason), [
            "No other hat to switch to",
            "Auto-switch is off",
            "Hats does not switch on this limit",
            "Hats was not running",
        ])
        XCTAssertEqual(HatsCopy.getLimitNoticeTitle(hat: "Work", limit: .sevenDay, percent: 81), "Work — weekly 81%")
        XCTAssertEqual(HatsCopy.getLimitNoticeTitle(hat: "Work", limit: .fiveHour, percent: 72), "Work — 5-hour 72%")
        XCTAssertEqual(HatsCopy.getLimitNoticeBody(stage: .warned, reason: .autoSwitchOff, save: 80),
                       "Auto-switch is off. Sessions anchor at 80%.")
        XCTAssertEqual(HatsCopy.getLimitNoticeBody(stage: .warned, reason: .hatsNotRunning, save: nil),
                       "Hats was not running. Sessions are told.")
        XCTAssertEqual(HatsCopy.getLimitNoticeBody(stage: .asked, reason: .switchThresholdOff, save: 80),
                       "Hats does not switch on this limit. Sessions anchor at the end of their turn.")
    }

    func testAWarningWithTheAnchorThresholdOffSaysSessionsAreTold() {
        let notices = createNotices()

        notices.noteARead(read(["a": [episode([event(.warned, reason: .switchThresholdOff)], save: nil)]]))

        XCTAssertEqual(bodies, ["Hats does not switch on this limit. Sessions are told."])
    }

    func testANullWindowStageIsNoWindowNotice() {
        var windowTold: [String] = []
        let windows = ContextThresholdNotices(notify: { windowTold.append($0.title) })
        let quiet = windowStage("a", kind: nil)
        let speaker = windowStage("b", kind: .requested)
        windows.noteARead(SessionStagesRead(stages: [], listed: []), windows: [])

        windows.noteARead(SessionStagesRead(stages: [quiet, speaker], listed: ["a", "b"]), windows: [])

        XCTAssertEqual(windowTold.count, 1, "only the session with a window stage is told: \(windowTold)")
    }

    func testTheChannelTellsALimitEventWrittenAfterTheLaunchWithTheHatsTitle() throws {
        let launchedAt = Date()
        let folder = root.appendingPathComponent(WindowThresholdsFile.stageFolderName)
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        let at = stamp.string(from: launchedAt.addingTimeInterval(1))
        let limits: [String: Any] = [
            "five_hour": SessionStageLimitsTests.episode(warned: SessionStageLimitsTests.event(at, percent: 72)),
            "seven_day": NSNull(),
        ]
        var fields = SessionStageFileTests.fields(["stage": NSNull(), "limits": limits])
        fields["at"] = stamp.string(from: launchedAt)
        try JSONSerialization.data(withJSONObject: fields).write(to: folder.appendingPathComponent("5a32129e-d019.json"))
        var titles: [String] = []
        let told = expectation(description: "the limit event is told")
        let channel = ContextThresholdsChannel(
            root: root,
            launchedAt: launchedAt,
            notify: { content in
                titles.append(content.title)
                told.fulfill()
            },
            pollEvery: 0.3,
            log: { _, _ in }
        )
        channel.hatTitle = { $0 == "work" ? "Work" : $0 }

        channel.start { [] }
        defer { channel.stop() }
        wait(for: [told], timeout: 5)

        XCTAssertEqual(titles, ["Work — 5-hour 72%"])
    }
}
