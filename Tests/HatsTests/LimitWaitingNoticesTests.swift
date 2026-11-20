import UserNotifications
import XCTest
@testable import Hats

final class LimitWaitingNoticesTests: XCTestCase {
    private var root: URL!
    private var told: [UNMutableNotificationContent] = []
    private var lines: [(String, [String: String])] = []
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private let launch = Date(timeIntervalSince1970: 1_800_000_000.250)
    private let resets = Date(timeIntervalSince1970: 1_800_010_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("limit-waiting-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func createNotices() -> LimitThresholdNotices {
        let notices = LimitThresholdNotices(
            root: root,
            launchedAt: launch,
            notify: { [unowned self] in told.append($0) },
            log: { [unowned self] event, details in lines.append((event, details)) },
            now: { [unowned self] in clock }
        )
        notices.hatTitle = { $0 == "work" ? "Work" : $0 }

        return notices
    }

    private func asked(after seconds: TimeInterval) -> LimitEvent {
        LimitEvent(stage: .asked, at: launch.addingTimeInterval(seconds), percent: 81.5, worn: "work", reason: .noHat)
    }

    private func waiting(
        after seconds: TimeInterval,
        origin: LimitWaitOrigin = .hat,
        minutes: Int = 10,
        cancelledAt: Date? = nil
    ) -> LimitEvent {
        var event = asked(after: seconds)
        event.wait = LimitWait(
            until: launch.addingTimeInterval(seconds + 600),
            origin: origin,
            drainMinutes: minutes,
            cancelledAt: cancelledAt
        )

        return event
    }

    private func read(_ sessions: [String: [LimitEvent]]) -> SessionStagesRead {
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
                limitEpisodes: [
                    LimitEpisode(
                        limit: .fiveHour,
                        resetsAt: resets,
                        percent: 81.5,
                        warnPercent: 70,
                        savePercent: 80,
                        events: sessions[session] ?? []
                    ),
                ],
                limitTrouble: nil
            )
        }

        return SessionStagesRead(stages: stages, listed: Set(sessions.keys))
    }

    private var alerts: [[String: String]] { lines.filter { $0.0 == "limit.alert" }.map(\.1) }

    func testTheTextsOfTheWaitingAnchorNotice() {
        XCTAssertEqual(
            HatsCopy.getLimitWaitNoticeBody(reason: .noHat, origin: .hat, minutes: 10),
            "No other hat to switch to. Sessions anchor at the end of their turn, after their background work "
                + "(up to 10 min from the first warning on this hat)."
        )
        XCTAssertEqual(
            HatsCopy.getLimitWaitNoticeBody(reason: .autoSwitchOff, origin: .warned, minutes: 5),
            "Auto-switch is off. Sessions anchor at the end of their turn, after their background work "
                + "(up to 5 min from their warning)."
        )
        XCTAssertEqual(
            HatsCopy.getLimitWaitNoticeBody(reason: .switchThresholdOff, origin: .deferred, minutes: 1),
            "Hats does not switch on this limit. Sessions anchor at the end of their turn, after their background work "
                + "(up to 1 min)."
        )
    }

    func testAWaitingThenAnAskOfTheSameEpisodeAreToldOnceWithTheWaitingText() throws {
        let notices = createNotices()

        notices.noteARead(read(["a": [waiting(after: 60, origin: .warned, minutes: 7)]]))
        notices.noteARead(read(["a": [waiting(after: 60, origin: .warned, minutes: 7), asked(after: 400)]]))

        XCTAssertEqual(told.map(\.title), ["Work — 5-hour 81%"])
        XCTAssertEqual(told.map(\.body), [HatsCopy.getLimitWaitNoticeBody(reason: .noHat, origin: .warned, minutes: 7)])
        XCTAssertEqual(alerts.map { $0["stage"] }, ["waiting"])
        XCTAssertEqual(alerts.first?["origin"], "warned")
        XCTAssertEqual(alerts.first?["drain_minutes"], "7")
        let entries = LimitNoticesFile(root: root, log: { _, _ in }).getEntries()
        XCTAssertEqual(entries.map(\.stage), [.asked], "one key for the anchor stage, whichever event came first")
        XCTAssertEqual(entries.first?.toldAt, launch.addingTimeInterval(400), "the later ask refreshed the key")
    }

    func testAnAskOfOneSessionThenAWaitingOfAnotherInTheSameEpisodeAreToldOnce() {
        let notices = createNotices()

        notices.noteARead(read(["a": [asked(after: 60)]]))
        notices.noteARead(read(["a": [asked(after: 60)], "b": [waiting(after: 120)]]))

        XCTAssertEqual(told.map(\.body), ["No other hat to switch to. Sessions anchor at the end of their turn."])
    }

    func testAWaitingBeforeTheLaunchLeavesTheNoticeToTheAskAfterIt() {
        let notices = createNotices()

        notices.noteARead(read(["a": [waiting(after: -30)]]))
        notices.noteARead(read(["a": [waiting(after: -30), asked(after: 60)]]))

        XCTAssertEqual(told.map(\.body), ["No other hat to switch to. Sessions anchor at the end of their turn."])
        XCTAssertEqual(alerts.map { $0["stage"] }, ["asked"])
    }

    func testACancelledWaitingStillCountsForTheNotice() {
        let notices = createNotices()

        notices.noteARead(read(["a": [waiting(after: 60, origin: .deferred, cancelledAt: launch.addingTimeInterval(90))]]))

        XCTAssertEqual(told.map(\.body), [HatsCopy.getLimitWaitNoticeBody(reason: .noHat, origin: .deferred, minutes: 10)])
    }

    func testTheOldEntriesAreNotChangedByTheWaitingKey() throws {
        let earlier = LimitNoticeEntry(hat: "work", limit: .sevenDay, stage: .warned, resetsAt: resets, toldAt: launch)
        var file = LimitNoticesFile(root: root, log: { _, _ in })
        file.setEntries([earlier])
        let notices = createNotices()

        notices.noteARead(read(["a": [waiting(after: 60)]]))

        let entries = file.getEntries()
        XCTAssertEqual(entries.first, earlier)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.last?.stage, .asked)
    }
}
