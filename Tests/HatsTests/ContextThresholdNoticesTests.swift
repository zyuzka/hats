import UserNotifications
import XCTest
@testable import Hats

final class ContextThresholdNoticesTests: XCTestCase {
    private var told: [UNMutableNotificationContent] = []
    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    private func createNotices() -> ContextThresholdNotices {
        ContextThresholdNotices(notify: { [unowned self] content in told.append(content) })
    }

    private func stage(
        _ kind: SessionStageKind,
        warn: Int,
        save: Int,
        session: String = "5a32129e-d019",
        percent: Int? = 56,
        thresholds: (Int?, Int?) = (45, 55)
    ) -> SessionStage {
        SessionStage(
            session: session,
            cwd: "/Volumes/work/projects/hats",
            kind: kind,
            warnRound: warn,
            saveRound: save,
            percent: percent,
            warnPercent: thresholds.0,
            savePercent: thresholds.1,
            at: at
        )
    }

    private func window(_ session: String, title: String?) -> SessionWindow {
        SessionWindow(
            session: session,
            cwd: "/elsewhere",
            title: title,
            tokens: 1,
            window: nil,
            percent: nil,
            state: .read,
            measuredAt: at
        )
    }

    private func read(_ stages: [SessionStage], alsoListed: [String] = []) -> SessionStagesRead {
        SessionStagesRead(stages: stages, listed: Set(stages.map(\.session) + alsoListed))
    }

    private var titles: [String] { told.map(\.title) }
    private var bodies: [String] { told.map(\.body) }

    func testTheTextsOfTheContextTab() {
        XCTAssertEqual(HatsCopy.warnAt, "Warn at")
        XCTAssertEqual(HatsCopy.anchorAt, "Anchor at")
        XCTAssertEqual(HatsCopy.afterAnchoring, "After anchoring")
        XCTAssertEqual(AfterSave.allCases.map(HatsCopy.getAfterSaveTitle), [
            "Only tell me",
            "Tell me and offer /clear",
            "Tell me and offer /exit and a new session",
            "Clear and go on from the note",
        ])
        XCTAssertEqual(
            HatsCopy.contextThresholdsNote,
            "Needs the session handoff plugin, with mods on in Claude Code 2.1.323 or later. A session is told once "
                + "per threshold, again after its context gets smaller; an idle session hears of it with its next "
                + "message. A session already past the lower threshold at its first answer gets neither."
        )
    }

    func testTheTextsOfTheNotices() {
        XCTAssertEqual(HatsCopy.getContextNoticeTitle(label: "Fix the login", percent: 47), "Fix the login — context 47%")
        XCTAssertEqual(HatsCopy.getWarnNoticeBody(warn: 45, save: 55),
                       "Past the warning threshold of 45%. The session anchors at 55%.")
        XCTAssertEqual(HatsCopy.getWarnNoticeBody(warn: 45, save: nil), "Past the warning threshold of 45%.",
                       "with the anchor threshold off there is no second sentence")
        XCTAssertEqual(HatsCopy.getAnchorNoticeBody(save: 55), "Past 55%: the session anchors at the end of its turn.")
        XCTAssertEqual(
            HatsCopy.getClearNoticeBody(save: 55),
            "Past 55%: the session anchors at the end of its turn and, if nothing stands in the way, clears its context "
                + "and goes on from its note."
        )
    }

    func testAnAnchorRoundWithTheClearActionSaysTheSessionMayClearAndKeptOrClearedTellNothingMore() {
        let notices = createNotices()
        notices.noteARead(read([]), windows: [])
        var requested = stage(.requested, warn: 0, save: 1)
        requested.afterSave = .clear
        var cleared = stage(.cleared, warn: 0, save: 1)
        cleared.afterSave = .clear
        var kept = stage(.kept, warn: 0, save: 1, session: "other")
        kept.afterSave = .clear

        notices.noteARead(read([requested]), windows: [])
        notices.noteARead(read([cleared]), windows: [])
        notices.noteARead(read([cleared, kept]), windows: [])
        notices.noteARead(read([cleared, kept]), windows: [])

        XCTAssertEqual(bodies, [
            HatsCopy.getClearNoticeBody(save: 55),
            HatsCopy.getClearNoticeBody(save: 55),
        ], "one notice per anchor round, the second for the other session; cleared and kept add none")
    }

    func testKeptOrClearedAfterTheRequestOfTheSameRoundTellNothingMore() {
        for kind in [SessionStageKind.kept, .cleared] {
            told = []
            let notices = createNotices()
            notices.noteARead(read([]), windows: [])
            var requested = stage(.requested, warn: 0, save: 1)
            requested.afterSave = .clear
            var later = stage(kind, warn: 0, save: 1)
            later.afterSave = .clear

            notices.noteARead(read([requested]), windows: [])
            notices.noteARead(read([later]), windows: [])

            XCTAssertEqual(bodies, [HatsCopy.getClearNoticeBody(save: 55)], "\(kind.rawValue) of the same session and round")
        }
    }

    func testTheFirstReadIsTheBaselineEvenWhenEmptyAndAnAnchorRequestAfterItIsToldOnce() {
        let notices = createNotices()

        notices.noteARead(read([]), windows: [])
        notices.noteARead(read([stage(.requested, warn: 1, save: 1)]), windows: [])
        notices.noteARead(read([stage(.requested, warn: 1, save: 1)]), windows: [])

        XCTAssertEqual(titles, ["hats — context 56%"], "the label falls back to the folder of the session")
        XCTAssertEqual(bodies, [HatsCopy.getAnchorNoticeBody(save: 55)])
    }

    func testWhatIsAlreadyThereAtTheFirstReadIsNotTold() {
        let notices = createNotices()
        let found = [
            stage(.requested, warn: 1, save: 1),
            stage(.warned, warn: 2, save: 0, session: "other"),
        ]

        notices.noteARead(read(found), windows: [])
        notices.noteARead(read(found), windows: [])
        XCTAssertEqual(told.count, 0)

        notices.noteARead(read([stage(.warned, warn: 3, save: 0, session: "other")]), windows: [])
        XCTAssertEqual(bodies, [HatsCopy.getWarnNoticeBody(warn: 45, save: 55)], "a later round of the same session is told")
    }

    func testAWarningIsToldWithTheAnchorThresholdOrWithoutItWhenItIsOff() {
        let notices = createNotices()
        notices.noteARead(read([]), windows: [])

        notices.noteARead(read([stage(.warned, warn: 1, save: 0, percent: 47)]), windows: [])
        notices.noteARead(read([stage(.warned, warn: 1, save: 0, session: "solo", percent: 47, thresholds: (45, nil))]), windows: [])

        XCTAssertEqual(titles, ["hats — context 47%", "hats — context 47%"])
        XCTAssertEqual(bodies, [
            HatsCopy.getWarnNoticeBody(warn: 45, save: 55),
            HatsCopy.getWarnNoticeBody(warn: 45, save: nil),
        ])
    }

    func testAWarningAlreadyToldIsNotToldAgainForTheSameRound() {
        let notices = createNotices()
        notices.noteARead(read([]), windows: [])

        notices.noteARead(read([stage(.warned, warn: 1, save: 0, percent: 47)]), windows: [])
        notices.noteARead(read([stage(.warned, warn: 1, save: 0, percent: 48)]), windows: [])
        notices.noteARead(read([stage(.warned, warn: 1, save: 0, session: "other", percent: 49)]), windows: [])

        XCTAssertEqual(titles, ["hats — context 47%", "hats — context 49%"],
                       "the same session and round read again is told once; another session's is told")
    }

    func testBothRoundsNewAtOnceGiveOneNoticeAboutAnchoring() {
        let notices = createNotices()
        notices.noteARead(read([]), windows: [])

        notices.noteARead(read([stage(.requested, warn: 1, save: 1)]), windows: [])
        notices.noteARead(read([stage(.warned, warn: 1, save: 0)]), windows: [])

        XCTAssertEqual(bodies, [HatsCopy.getAnchorNoticeBody(save: 55)],
                       "the warning it skipped is not told later, after the request is refused")
    }

    func testEveryStageFromRequestedOnTellsANewAnchorRound() {
        for kind in [SessionStageKind.requested, .saved, .failed, .interrupted, .kept, .cleared] {
            told = []
            let notices = createNotices()
            notices.noteARead(read([]), windows: [])

            notices.noteARead(read([stage(kind, warn: 0, save: 1)]), windows: [])

            XCTAssertEqual(bodies, [HatsCopy.getAnchorNoticeBody(save: 55)], kind.rawValue)
        }
    }

    func testTheNextRoundOfEachThresholdIsASecondNotice() {
        let notices = createNotices()
        notices.noteARead(read([]), windows: [])

        notices.noteARead(read([stage(.warned, warn: 1, save: 0)]), windows: [])
        notices.noteARead(read([stage(.saved, warn: 1, save: 1)]), windows: [])
        notices.noteARead(read([stage(.warned, warn: 2, save: 1)]), windows: [])
        notices.noteARead(read([stage(.requested, warn: 2, save: 2)]), windows: [])

        XCTAssertEqual(bodies, [
            HatsCopy.getWarnNoticeBody(warn: 45, save: 55),
            HatsCopy.getAnchorNoticeBody(save: 55),
            HatsCopy.getWarnNoticeBody(warn: 45, save: 55),
            HatsCopy.getAnchorNoticeBody(save: 55),
        ])
    }

    func testAManualAnchorAndAWarnedStageWithOnlyANewAnchorRoundTellNothing() {
        let notices = createNotices()
        notices.noteARead(read([stage(.warned, warn: 1, save: 1)]), windows: [])

        notices.noteARead(read([stage(.saved, warn: 1, save: 1)]), windows: [])
        notices.noteARead(read([stage(.warned, warn: 1, save: 2)]), windows: [])
        notices.noteARead(read([stage(.requested, warn: 1, save: 3)]), windows: [])

        XCTAssertEqual(bodies, [HatsCopy.getAnchorNoticeBody(save: 55)],
                       "a manual anchor keeps its round; a new anchor round is told only from requested on")
    }

    func testAManualAnchorBeforeAnyRoundTellsNothing() {
        let notices = createNotices()
        notices.noteARead(read([]), windows: [])

        notices.noteARead(read([stage(.saved, warn: 0, save: 0)]), windows: [])
        notices.noteARead(read([stage(.requested, warn: 0, save: 1, session: "other")]), windows: [])

        XCTAssertEqual(bodies, [HatsCopy.getAnchorNoticeBody(save: 55)],
                       "a session anchored by hand past 55% before any request has round 0, which is no crossing")
    }

    func testAWarningRoundFirstSeenAtALaterStageIsNotTold() {
        let notices = createNotices()
        notices.noteARead(read([stage(.saved, warn: 0, save: 1)]), windows: [])

        notices.noteARead(read([stage(.saved, warn: 1, save: 1)]), windows: [])
        notices.noteARead(read([stage(.warned, warn: 2, save: 1)]), windows: [])

        XCTAssertEqual(bodies, [HatsCopy.getWarnNoticeBody(warn: 45, save: 55)],
                       "the warning is told only while the stage is warned, as the mod wrote it")
    }

    func testWhatWasToldIsRememberedWhileTheFileIsUnreadable() {
        let notices = createNotices()
        notices.noteARead(read([]), windows: [])

        notices.noteARead(read([stage(.requested, warn: 1, save: 1)]), windows: [])
        notices.noteARead(read([], alsoListed: ["5a32129e-d019"]), windows: [])
        notices.noteARead(read([stage(.requested, warn: 1, save: 1)]), windows: [])
        notices.noteARead(read([stage(.requested, warn: 1, save: 1, session: "other")]), windows: [])

        XCTAssertEqual(titles, ["hats — context 56%", "hats — context 56%"],
                       "the same round read again after a gap is not told; another session's is")
        XCTAssertEqual(told.count, 2)
    }

    func testASessionWhoseFileIsGoneIsForgottenSoItsRestartedRoundsAreToldAgain() {
        let notices = createNotices()
        notices.noteARead(read([]), windows: [])

        notices.noteARead(read([stage(.requested, warn: 1, save: 1)]), windows: [])
        notices.noteARead(read([]), windows: [])
        notices.noteARead(read([stage(.requested, warn: 1, save: 1)]), windows: [])

        XCTAssertEqual(told.count, 2, "a swept file's session counts its rounds from 1 again when it resumes")
    }

    func testAFileSkippedAtTheFirstReadIsTheBaselineWhenItFirstReadsCleanly() {
        let notices = createNotices()
        notices.noteARead(read([], alsoListed: ["5a32129e-d019"]), windows: [])

        notices.noteARead(read([stage(.requested, warn: 1, save: 1)]), windows: [])
        notices.noteARead(read([stage(.requested, warn: 1, save: 2, percent: 58)]), windows: [])

        XCTAssertEqual(titles, ["hats — context 58%"],
                       "the round that lay there half-written before Hats started is not told; the next one is")
    }

    func testANoticeWithoutAPercentWaitsForARecordThatHasOne() {
        let notices = createNotices()
        notices.noteARead(read([]), windows: [])

        notices.noteARead(read([stage(.requested, warn: 1, save: 1, percent: nil)]), windows: [])
        XCTAssertEqual(told.count, 0)
        notices.noteARead(read([stage(.requested, warn: 1, save: 1, percent: 57)]), windows: [])

        XCTAssertEqual(titles, ["hats — context 57%"])
    }

    func testTheNoticeIsNamedAfterTheSessionTitleFromItsWindowFile() {
        let notices = createNotices()
        notices.noteARead(read([]), windows: [])

        notices.noteARead(read([stage(.requested, warn: 1, save: 1)]), windows: [
            window("other", title: "Not this one"),
            window("5a32129e-d019", title: "Fix the login"),
        ])
        notices.noteARead(read([stage(.requested, warn: 1, save: 1, session: "3b9e")]), windows: [window("3b9e", title: nil)])

        XCTAssertEqual(titles, [
            HatsCopy.getContextNoticeTitle(label: "Fix the login", percent: 56),
            HatsCopy.getContextNoticeTitle(label: "hats", percent: 56),
        ])
    }

    func testTheNoticeShowsAsABannerWithHatsInFrontAndOpensNothing() throws {
        let notices = createNotices()
        notices.noteARead(read([]), windows: [])

        notices.noteARead(read([stage(.requested, warn: 1, save: 1)]), windows: [])

        let content = try XCTUnwrap(told.first)
        XCTAssertEqual(Notifier.getPresentation(content.userInfo), [.banner, .list])
        XCTAssertFalse(Notifier.isClickOpeningSettings(UNNotificationDefaultActionIdentifier, content.userInfo))
        XCTAssertEqual(Notifier.getPresentation([:]), [], "other notifications stay hidden in front, as before")
        XCTAssertEqual(Notifier.getPresentation([Notifier.showsInFrontKey: "yes"]), [])
    }
}
