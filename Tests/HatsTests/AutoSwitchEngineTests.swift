import XCTest
@testable import Hats

final class AutoSwitchEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let resetsAt = Date(timeIntervalSince1970: 1_800_003_600)

    private func reading(_ percent: Int) -> UsageReading {
        UsageReading(session: UsageWindow(used: percent, limit: 100, resetsAt: resetsAt), weekly: nil)
    }

    private func hat(_ id: String, _ name: String, switchable: Bool = true) -> Account {
        var hat = Account(id: id, email: "\(id)@x.co", browser: nil)
        hat.name = name
        hat.hasStoredCredentials = switchable
        if switchable { hat.identity = CLIIdentity(oauthAccount: [:], userID: nil) }
        return hat
    }

    private var armed: AutoSwitchPolicy {
        var policy = AutoSwitchPolicy()
        policy.isOn = true
        policy.order = ["personal", "team"]
        return policy
    }

    private func outcome(
        _ policy: AutoSwitchPolicy,
        readings: [String: UsageReading],
        wearing: String? = "work",
        eligible: [String] = ["work", "personal", "team"],
        at when: Date? = nil,
        blindness: UsageBlindness = UsageBlindness()
    ) -> AutoSwitchOutcome {
        AutoSwitchEngine.outcome(
            policy: policy,
            world: AutoSwitchWorld(readings: readings, wearing: wearing,
                                   eligible: eligible, blindness: blindness),
            now: when ?? now
        )
    }

    private func blind(
        _ missedPolls: Int,
        fresh: Set<String> = [],
        read: Bool = true,
        landed: Bool = true
    ) -> UsageBlindness {
        UsageBlindness(missedPolls: missedPolls, hasReadTheWornHatSinceItWentOn: read,
                       fresh: fresh, landedAPoll: landed)
    }

    func testOnlyTheWornHatsReadingDecides() {
        XCTAssertEqual(outcome(armed, readings: ["personal": reading(99)]), .hold,
                       "the only reading held belongs to a parked hat, and a parked hat's usage is "
                           + "not a reason to take off the one being worn")
        XCTAssertEqual(outcome(armed, readings: ["work": reading(10), "personal": reading(99)]), .hold)
        XCTAssertEqual(outcome(armed, readings: ["work": reading(95)]).wearsHat, "personal")
    }

    func testFiringWritesTheRecordTheBannerNeeds() throws {
        let fired = outcome(armed, readings: ["work": reading(95)])
        let record = try XCTUnwrap(fired.record)
        XCTAssertEqual(record.from, "work")
        XCTAssertEqual(record.to, "personal")
        XCTAssertEqual(record.limit, .session)
        XCTAssertEqual(record.resetsAt, resetsAt)
        XCTAssertEqual(record.firedAt, now)
        XCTAssertFalse(record.seenInPopover, "the banner has not been shown yet")
    }

    func testAWindowThatResetElsewhereMovesNothingByItself() {
        let after = outcome(armed, readings: ["personal": reading(22), "work": reading(0)],
                            wearing: "personal", at: resetsAt.addingTimeInterval(1))
        XCTAssertEqual(after, .hold,
                       "measured twice on 2026-09-04: the app left a hat reading 7/100 and then one "
                           + "reading 22/100 because the hat it had come from had its window reset, "
                           + "which spends a switch to gain nothing")
    }

    func testEveryHatBeingSpentIsItsOwnAnswerRatherThanSilence() {
        let stuck = outcome(armed, readings: ["work": reading(95), "personal": reading(97),
                                             "team": reading(99)])
        XCTAssertEqual(stuck.decision, .nowhereToGo(.atALimit(.session, .othersAreSpent(freesUpAt: resetsAt))))
        XCTAssertNil(stuck.wearsHat, "there is nowhere to go, so nothing is worn")
        XCTAssertNil(stuck.record, "no switch happened, so there is no switch to describe")
        XCTAssertFalse(stuck.notifies,
                       "a poll every five minutes would notify every five minutes; the journal "
                           + "carries this one and the screen does not")
    }

    func testWithNoHatWornThereIsNothingToSwitchAwayFrom() {
        XCTAssertEqual(outcome(armed, readings: ["work": reading(99)], wearing: nil), .hold)
    }

    func testEligibilityIsReadOffTheRowsTheListShows() {
        let rows = [
            HatRowState(hat: hat("work", "Work"), isWearing: true, usage: nil, usageTrouble: nil),
            HatRowState(hat: hat("personal", "Personal"), isWearing: false, usage: nil, usageTrouble: nil),
            HatRowState(hat: hat("team", "Team", switchable: false), isWearing: false, usage: nil, usageTrouble: nil),
        ]
        XCTAssertEqual(AutoSwitchEngine.eligible(in: rows), ["work", "personal"],
                       "a hat that cannot be worn is not a destination")
        XCTAssertEqual(AutoSwitchEngine.blocked(in: rows).map(\.id), ["team"],
                       "and it is not invisible either: the dead end has to tell \"there is no "
                           + "other hat\" apart from \"the other one only needs signing in\", and "
                           + "the second is the case the person can fix in ten seconds")
    }

    func testTheNoticeNamesBothHatsAndIsSilentWhenTheUserAskedForSilence() throws {
        let titles = ["work": "Work", "personal": "Personal"]
        let fired = outcome(armed, readings: ["work": reading(95)])
        let notice = try XCTUnwrap(AutoSwitchEngine.notice(for: fired) { titles[$0] ?? $0 })
        XCTAssertEqual(notice.0, "Switched to Personal")
        XCTAssertEqual(notice.1, "Work reached its 5-hour limit.")

        var quiet = armed
        quiet.notifies = false
        let silent = outcome(quiet, readings: ["work": reading(95)])
        XCTAssertNil(AutoSwitchEngine.notice(for: silent) { titles[$0] ?? $0 },
                     "the switch still happens; only the notification is withheld")
        XCTAssertEqual(silent.wearsHat, "personal")
    }

    func testHoldingNeverProducesANotice() {
        let held = outcome(armed, readings: ["work": reading(10)])
        XCTAssertNil(AutoSwitchEngine.notice(for: held) { $0 })
    }

    func testASwitchMadeBlindIsToldApartByItsCauseRatherThanByAMissingLimit() throws {
        let fired = outcome(armed, readings: ["work": reading(89), "personal": reading(0)],
                            blindness: blind(2, fresh: ["personal"]))
        let record = try XCTUnwrap(fired.record)
        XCTAssertEqual(fired.wearsHat, "personal")
        XCTAssertEqual(record.from, "work")
        XCTAssertEqual(record.cause, .usageCouldNotBeRead)
        XCTAssertEqual(record.limit, .session,
                       "the window it was watching is written even though nothing was crossed: a "
                           + "build without the cause field requires this key, and a record "
                           + "without it would take every other setting down with it there. What "
                           + "tells the two switches apart is the cause, not an absent limit")
        XCTAssertNil(record.resetsAt, "and no window was crossed, so nothing comes back at a time")
        XCTAssertEqual(record.firedAt, now)
        XCTAssertEqual(record.journalReason, "usageCouldNotBeRead",
                       "the journal is the fourth place the reason is named, and now that the "
                           + "record carries a limit for the older build to read, the limit is "
                           + "exactly what must not be written here - it would report a threshold "
                           + "that was never crossed")

        let byLimit = try XCTUnwrap(outcome(armed, readings: ["work": reading(95)]).record)
        XCTAssertEqual(byLimit.cause, .reachedALimit)
        XCTAssertEqual(byLimit.limit, .session)
        XCTAssertEqual(byLimit.journalReason, "session", "and the limit path writes what it always did")
    }

    func testTheBlindNoticeNamesTheWindowItWasMeasuringAndTheNumberItLastSaw() throws {
        let titles = ["work": "Work", "personal": "Personal"]
        let fired = outcome(armed, readings: ["work": reading(89), "personal": reading(0)],
                            blindness: blind(2, fresh: ["personal"]))
        let notice = try XCTUnwrap(
            AutoSwitchEngine.notice(for: fired, lastSeen: 1298) { titles[$0] ?? $0 }
        )
        XCTAssertEqual(notice.0, "Switched to Personal")
        XCTAssertEqual(notice.1,
                       "Hats couldn't read Work's usage. Its 5-hour limit was at 89% when last "
                           + "seen 21m ago.",
                       "one slot and two windows, so the window is named: \"it was at 88%\" "
                           + "against a five-hour figure of 40 would say the wrong thing about the "
                           + "wrong window. And the age is the whole subject of this branch - a "
                           + "percentage with no date reads as current, which is the very mistake "
                           + "the switch was made to answer")
        let undated = try XCTUnwrap(AutoSwitchEngine.notice(for: fired) { titles[$0] ?? $0 })
        XCTAssertEqual(undated.1,
                       "Hats couldn't read Work's usage. Its 5-hour limit was at 89% when last seen.",
                       "with no stamp to measure from, the sentence says less rather than guessing")

        var quiet = armed
        quiet.notifies = false
        let silent = outcome(quiet, readings: ["work": reading(89), "personal": reading(0)],
                             blindness: blind(2, fresh: ["personal"]))
        XCTAssertNil(AutoSwitchEngine.notice(for: silent) { titles[$0] ?? $0 })
        XCTAssertEqual(silent.wearsHat, "personal", "the switch still happens")
    }

    func testTheWarningIsRaisedOnceAnEpisodeAndNeverAwayFromAThreshold() {
        let near = outcome(armed, readings: ["work": reading(89)], blindness: blind(1))
        XCTAssertEqual(AutoSwitchWarning.of(decision: near.decision, holding: .blindAndNear,
                                            blindness: blind(1)),
                       .willSwitchWhenItCan)
        XCTAssertEqual(AutoSwitchWarning.of(decision: .hold, holding: .blindTargetSpent,
                                            blindness: blind(2, fresh: ["personal"])),
                       .everyOtherHatIsSpent,
                       "the step was reached and nothing had room, so this is a dead end - but not "
                           + "the same dead end: here the other hats were read and are full, so "
                           + "saying they have no fresh reading would be false, and promising \"it "
                           + "will switch as soon as it can\" would be a promise already broken")
        XCTAssertNil(AutoSwitchWarning.of(decision: near.decision, holding: .blindAndFar,
                                          blindness: blind(3)),
                     "429 lands six to ten times a day; a dot for every one of them would stop "
                         + "meaning anything")
        XCTAssertNil(AutoSwitchWarning.of(decision: near.decision, holding: .underTheThresholds,
                                          blindness: blind(0)))
        XCTAssertEqual(AutoSwitchWarning.of(decision: .nowhereToGo(.noFreshReading),
                                            holding: nil, blindness: blind(2)),
                       .nowhereFreshToGo,
                       "without this line the warning above is a promise the app then quietly "
                           + "fails to keep")
        XCTAssertEqual(AutoSwitchWarning.of(
            decision: .nowhereToGo(.atALimit(.session, .othersAreSpent(freesUpAt: resetsAt))),
            holding: nil,
            blindness: blind(2)
        ),
                       .nowhereToGoAtALimit(.session, .othersAreSpent(freesUpAt: resetsAt)),
                       "this used to be the quiet answer, and quiet is what it cost: measured on "
                           + "2026-09-25, an hour of autoSwitch.nowhereToGo every five minutes in "
                           + "the journal, no dot, no notification, and the person found out by "
                           + "hitting the limit")
        XCTAssertNil(AutoSwitchWarning.of(decision: near.decision, holding: .blindAndNear,
                                          blindness: blind(1, landed: false)),
                     "the warning is an event of a poll landing, not a state a redraw can raise")
        XCTAssertNil(AutoSwitchWarning.of(decision: .hold, holding: .off, blindness: blind(2)),
                     "with auto-switching off the person gets nothing at all - no dot, no "
                         + "notification, no move")
        XCTAssertNil(AutoSwitchWarning.of(decision: .hold, holding: .noReading, blindness: blind(2)),
                     "a hat with no number at all is its own older problem and keeps its own answer")
    }

    func testAPollThatSwitchesRaisesNoWarningAlongsideTheSwitch() {
        let fired = outcome(armed, readings: ["work": reading(89), "personal": reading(0)],
                            blindness: blind(2, fresh: ["personal"]))
        let holding = AutoSwitchEngine.reasonForHolding(
            policy: armed,
            world: AutoSwitchWorld(readings: ["work": reading(89), "personal": reading(0)],
                                   wearing: "work",
                                   eligible: ["work", "personal", "team"],
                                   blindness: blind(2, fresh: ["personal"]))
        )
        XCTAssertNil(holding, "nothing is being held; the hat is moving")
        XCTAssertNil(AutoSwitchWarning.of(decision: fired.decision, holding: holding,
                                          blindness: blind(2, fresh: ["personal"])),
                     "this is the pair the app actually produces on a switching poll, and it is "
                         + "the pair no test fed in before: a reason invented next to a firing "
                         + "decision reached the warning, so the person got \"Can't read usage\" "
                         + "and \"Switched to Personal\" in the same instant")
        XCTAssertNil(AutoSwitchWarning.of(decision: fired.decision, holding: .blindTargetSpent,
                                          blindness: blind(2, fresh: ["personal"])),
                     "and even handed a reason that disagrees with it, a decision that moves a hat "
                         + "warns about nothing - two guards, because one of them is the one that "
                         + "already failed")
        XCTAssertNil(AutoSwitchWarning.of(decision: .fire(to: "personal", limit: .session, resetsAt: nil),
                                          holding: .blindAndNear, blindness: blind(2)),
                     "the same holds for the older path, where the limit decides")
    }

    func testTheWorldIsBuiltTheSameWayEverywhereAndOnlyAPollCarriesTheBlindness() {
        var snapshot = HatsSnapshot()
        snapshot.rows = [
            HatRowState(hat: hat("work", "Work"), isWearing: true, usage: nil, usageTrouble: nil),
            HatRowState(hat: hat("personal", "Personal"), isWearing: false, usage: nil, usageTrouble: nil),
            HatRowState(hat: hat("team", "Team", switchable: false), isWearing: false,
                        usage: nil, usageTrouble: nil),
        ]
        var missed = MissedPolls()
        missed = missed.settled(wearing: "work", fresh: ["work"], from: .timer, every: 300, at: now)
        missed = missed.settled(wearing: "work", fresh: [], from: .timer, every: 300,
                                at: now.addingTimeInterval(300))
        missed = missed.settled(wearing: "work", fresh: [], from: .timer, every: 300,
                                at: now.addingTimeInterval(600))

        let readings = ["work": reading(89), "personal": reading(0)]
        let polled = AutoSwitchWorld.of(snapshot: snapshot, readings: readings,
                                        missed: missed, fresh: ["personal"], from: .aPollLanded)
        XCTAssertEqual(polled.readings, readings,
                       "every reading reaches the decision, not only the worn hat's - the target "
                           + "is chosen from them")
        XCTAssertEqual(polled.blindness.fresh, ["personal"],
                       "which hats answered this poll is the whole basis for choosing a blind "
                           + "target; an empty set here would switch nothing off loudly, it would "
                           + "just never switch again")
        XCTAssertTrue(polled.blindness.hasReadTheWornHatSinceItWentOn,
                      "and without this the branch is dead in both directions - no warning and no "
                          + "switch, for ever, with every other test still green because they all "
                          + "build UsageBlindness by hand")
        XCTAssertTrue(polled.blindness.isBlindEnoughToSwitch,
                      "the whole point of the transfer: two missed polls collected by the watch "
                          + "have to arrive as two missed polls at the decision")
        XCTAssertEqual(
            AutoSwitchEngine.outcome(policy: armed, world: polled, now: now).wearsHat,
            "personal",
            "and the assembled world, not a hand-made one, moves the hat"
        )
        XCTAssertEqual(polled, AutoSwitchWorld(
            readings: readings,
            wearing: "work",
            eligible: ["work", "personal"],
            blocked: [ShutOutHat(id: "team", title: "Team", blocker: "needs login",
                                 loginAction: "Log in…")],
            blindness: UsageBlindness(missedPolls: 2, hasReadTheWornHatSinceItWentOn: true,
                                      fresh: ["personal"], landedAPoll: true)
        ),
                       "the WHOLE world is compared, field by field, because this adapter is the "
                           + "only door everything takes into the decision and it has now dropped "
                           + "a field four times: fresh, the isOn guard, the held warning, and "
                           + "blocked - each time one line switched a working feature off with the "
                           + "suite green. A field-by-field list would age; an equality over the "
                           + "value cannot, because a field added tomorrow joins it by itself. "
                           + "That only works while EVERY field here is set to something other "
                           + "than its default, so a dropped field shows up as a difference - "
                           + "which is why this fixture carries a hat that cannot be worn")

        for quiet in [AutoSwitchCall.thePopoverOpened, .theToggleChanged] {
            let world = AutoSwitchWorld.of(snapshot: snapshot, readings: ["work": reading(89)],
                                           missed: missed, fresh: ["personal"], from: quiet)
            XCTAssertFalse(world.blindness.landedAPoll, "\(quiet) is not a poll landing")
            XCTAssertFalse(world.blindness.isBlindEnoughToSwitch,
                           "the count was collected by the polling, which runs whether the switch "
                               + "is on or not, so acting on it at \(quiet) would move the person "
                               + "in the second they touched the app")
        }
    }
}
