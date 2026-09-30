import XCTest
@testable import Hats

final class AutoSwitchPolicyTests: XCTestCase {
    func testAnEmptyOrShortOrderFallsBackToTheHatsAsTheyAreShown() {
        var policy = AutoSwitchPolicy()
        let all = ["work", "personal", "team"]
        XCTAssertEqual(policy.nextHat(after: "work", among: all, readings: [:]), "personal",
                       "the panel shows the unordered hats after the ordered ones, and the engine agrees with it")
        policy.order = ["team"]
        XCTAssertEqual(policy.nextHat(after: "work", among: all, readings: [:]), "team")
        policy.order = ["work"]
        XCTAssertEqual(policy.nextHat(after: "work", among: all, readings: [:]), "personal",
                       "an order naming only the worn hat still leaves the shown rest to fall back on")
        XCTAssertNil(policy.nextHat(after: "work", among: ["work"], readings: [:]),
                     "nothing else can be worn")
        policy.order = ["gone"]
        XCTAssertEqual(policy.nextHat(after: "work", among: ["work", "personal"], readings: [:]),
                       "personal",
                       "an ordered hat that is no longer eligible is skipped, not chosen")
    }

    func testAHatKnownToBeSpentIsNeverChosenAndTheOrderDecidesAmongTheRest() {
        var policy = AutoSwitchPolicy()
        policy.order = ["personal", "team"]
        let all = ["work", "personal", "team"]

        XCTAssertEqual(policy.nextHat(after: "work", among: all,
                                      readings: ["personal": reading(session: 96, weekly: 0),
                                                 "team": reading(session: 5, weekly: 5)]),
                       "team",
                       "the first hat in the order has no room left, and moving onto it buys a "
                           + "switch and no capacity")
        XCTAssertEqual(policy.nextHat(after: "work", among: all,
                                      readings: ["personal": reading(session: 5, weekly: 5),
                                                 "team": reading(session: 5, weekly: 5)]),
                       "personal",
                       "with room in both the order is what decides, as it always did")
    }

    func testAHatWhoseUsageIsUnknownIsTheLastResortRatherThanARefusal() {
        var policy = AutoSwitchPolicy()
        policy.order = ["personal", "team"]
        let all = ["work", "personal", "team"]

        XCTAssertEqual(policy.nextHat(after: "work", among: all,
                                      readings: ["team": reading(session: 5, weekly: 5)]),
                       "team",
                       "personal carries no reading; a hat measured to have room is the better bet")
        XCTAssertEqual(policy.nextHat(after: "work", among: all,
                                      readings: ["team": reading(session: 99, weekly: 0)]),
                       "personal",
                       "with the only measured hat spent, an unmeasured one is still worth trying - "
                           + "refusing to move because the meter is unreadable strands the person on "
                           + "a hat that is definitely out")
        XCTAssertNil(policy.nextHat(after: "work", among: all,
                                    readings: ["personal": reading(session: 99, weekly: 0),
                                               "team": reading(session: 99, weekly: 0)]),
                     "every candidate measured and every one spent")
    }

    func testTheRoomOfAHatIsThreeAnswersAndNotTwo() {
        var policy = AutoSwitchPolicy()
        policy.sessionThresholdPercent = 90
        policy.weeklyThresholdPercent = 95
        XCTAssertEqual(policy.room(for: "a", readings: ["a": reading(session: 5, weekly: 5)]), .free)
        XCTAssertEqual(policy.room(for: "a", readings: ["a": reading(session: 90, weekly: 5)]), .spent)
        XCTAssertEqual(policy.room(for: "a", readings: ["a": reading(session: 5, weekly: 95)]), .spent,
                       "the weekly window is a limit too, and a hat over it has no room whatever "
                           + "its five hours say")
        XCTAssertEqual(policy.room(for: "a", readings: [:]), .unknown)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let resetsAt = Date(timeIntervalSince1970: 1_800_003_600)

    private func reading(session: Int, weekly: Int) -> UsageReading {
        UsageReading(
            session: UsageWindow(used: session, limit: 100, resetsAt: resetsAt),
            weekly: UsageWindow(used: weekly, limit: 100, resetsAt: resetsAt)
        )
    }

    private var armed: AutoSwitchPolicy {
        var policy = AutoSwitchPolicy()
        policy.isOn = true
        policy.order = ["personal", "team"]
        return policy
    }

    private func decide(
        _ reading: UsageReading?,
        policy: AutoSwitchPolicy,
        wearing: String? = "work",
        eligible: [String] = ["work", "personal", "team"],
        readings: [String: UsageReading] = [:],
        blocked: [ShutOutHat] = [],
        blindness: UsageBlindness = UsageBlindness(),
        at when: Date? = nil
    ) -> AutoSwitchDecision {
        policy.decide(reading: reading, wearing: wearing, eligible: eligible,
                      readings: readings, blocked: blocked, blindness: blindness, at: when ?? now)
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

    func testAPolicyThatIsOffNeverMovesAHat() {
        var off = armed
        off.isOn = false
        XCTAssertEqual(decide(reading(session: 99, weekly: 99), policy: off), .hold)
    }

    func testBelowEveryThresholdItHolds() {
        XCTAssertEqual(decide(reading(session: 89, weekly: 94), policy: armed), .hold)
    }

    func testCrossingTheSessionThresholdMovesToTheFirstHatInOrder() {
        XCTAssertEqual(decide(reading(session: 90, weekly: 10), policy: armed),
                       .fire(to: "personal", limit: .session, resetsAt: resetsAt))
    }

    func testCrossingOnlyTheWeeklyThresholdNamesTheWeeklyLimit() {
        XCTAssertEqual(decide(reading(session: 10, weekly: 95), policy: armed),
                       .fire(to: "personal", limit: .weekly, resetsAt: resetsAt))
    }

    func testATriggerSwitchedOffIsNotConsulted() {
        var sessionOff = armed
        sessionOff.sessionThresholdPercent = nil
        XCTAssertEqual(decide(reading(session: 100, weekly: 10), policy: sessionOff), .hold,
                       "an unset threshold is a trigger the user turned off, not a threshold of zero")
    }

    func testTheOrderSkipsTheHatBeingWornAndAnyHatThatCannotBePutOn() {
        XCTAssertEqual(decide(reading(session: 95, weekly: 0), policy: armed, wearing: "personal"),
                       .fire(to: "team", limit: .session, resetsAt: resetsAt),
                       "the hat already on is not a destination")
        XCTAssertEqual(decide(reading(session: 95, weekly: 0), policy: armed,
                              eligible: ["work", "team"]),
                       .fire(to: "team", limit: .session, resetsAt: resetsAt),
                       "an expired hat is skipped, not put on")
    }

    func testNoOtherHatBeingWearableIsNowhereToGoRatherThanASilentHold() {
        XCTAssertEqual(decide(reading(session: 95, weekly: 0), policy: armed,
                              eligible: ["work"]), .nowhereToGo(.atALimit(.session, .noOtherHat)),
                       "the hat is over its limit and there is no second hat; that is a different "
                           + "state from being below every threshold and it used to share its answer")
        var empty = armed
        empty.order = []
        XCTAssertEqual(decide(reading(session: 95, weekly: 0), policy: empty),
                       .fire(to: "personal", limit: .session, resetsAt: resetsAt),
                       "an order nobody set is the order the panel shows, so the next shown hat goes on")
    }

    func testNoReadingMeansNoDecision() {
        XCTAssertEqual(decide(nil, policy: armed), .hold,
                       "OpenUsage being down is not evidence of anything")
    }

    func testAHatWithRoomIsNeverTakenOffNoMatterWhatResetElsewhere() {
        XCTAssertEqual(decide(reading(session: 22, weekly: 13), policy: armed, wearing: "personal",
                              readings: ["personal": reading(session: 22, weekly: 13),
                                         "work": reading(session: 0, weekly: 11)]),
                       .hold,
                       "the whole subject of this branch: a window resetting on another hat used to "
                           + "pull the person off one that had 78 percent of its own window left. "
                           + "The reset is expressed by work's own reading of zero used, not by a "
                           + "clock — the policy stopped consulting one when that rule went away, "
                           + "which is why the at: argument it used to take had no effect left")
    }

    func testWhenNothingHasRoomTheAnswerSaysSoAndNamesTheLimit() {
        XCTAssertEqual(decide(reading(session: 95, weekly: 5), policy: armed,
                              readings: ["work": reading(session: 95, weekly: 5),
                                         "personal": reading(session: 91, weekly: 5),
                                         "team": reading(session: 99, weekly: 5)]),
                       .nowhereToGo(.atALimit(.session, .othersAreSpent(freesUpAt: resetsAt))))
        XCTAssertEqual(decide(reading(session: 5, weekly: 96), policy: armed,
                              readings: ["work": reading(session: 5, weekly: 96),
                                         "personal": reading(session: 5, weekly: 96),
                                         "team": reading(session: 5, weekly: 96)]),
                       .nowhereToGo(.atALimit(.weekly, .othersAreSpent(freesUpAt: resetsAt))),
                       "which limit stranded us is the thing worth knowing, and it used to be a "
                           + "silent hold indistinguishable from being below every threshold")
    }

    func testANumberWithinTheMarginMovesNothingWhileThePollsKeepLanding() {
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(0, fresh: ["personal"])),
                       .hold,
                       "89 is inside the margin of the threshold of 90, and that on its own is not "
                           + "a reason for anything: the poll landed and read it, so the number is "
                           + "current and the app is working as asked")
    }

    func testTwoMissedPollsNearTheThresholdMoveToAHatReadInThisPoll() {
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["work": reading(session: 89, weekly: 0),
                                         "personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .fireBlind(to: "personal", lastSeen: LastLiveWindow(limit: .session, percent: 89)),
                       "the circumstances of 2026-09-21: the last live number was session=89/100 "
                           + "against a threshold of 90, the polls had been failing for twenty-one "
                           + "minutes, and a hat reading session=0/100 was sitting right there")
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(1, fresh: ["personal"])),
                       .hold,
                       "one missed poll warns and no more; a single blip is not worth a switch")
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(5, fresh: ["personal"])),
                       .fireBlind(to: "personal", lastSeen: LastLiveWindow(limit: .session, percent: 89)),
                       "the step is at least two, not exactly two - a target that turns up fresh on "
                           + "the fifth missed poll would otherwise never be reached")
    }

    func testABlindSwitchRefusesATargetThatIsItselfNearTheThreshold() {
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 85, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .hold,
                       "85 is under the threshold of 90 and still inside the margin, so it is both "
                           + "a lawful destination and a reason to leave - two hats at 85 and 89 "
                           + "would swap places on every poll, rewriting the keychain each time")
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 97, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .hold,
                       "a target over its own limit has no room to move into")
    }

    func testABlindSwitchOnlyEverGoesToAHatReadInThisVeryPoll() {
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2)),
                       .nowhereToGo(.noFreshReading),
                       "with the network down nothing is read, the target is as blind as the hat "
                           + "being worn, and swapping a known bad number for an unknown one is not "
                           + "an improvement")
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              eligible: ["work"], blindness: blind(2, fresh: ["personal"])),
                       .nowhereToGo(.noFreshReading),
                       "no limit was crossed, so there is no limit to name in the answer")
    }

    func testAHatWithNoNumberAtAllIsNeverTheBlindDestination() {
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["team": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal", "team"])),
                       .fireBlind(to: "team", lastSeen: LastLiveWindow(limit: .session, percent: 89)),
                       "personal comes first in the order and answered the poll with no usage at "
                           + "all; the fallback onto an unknown hat that the limit path allows is "
                           + "switched off here, because the whole point is to move onto room that "
                           + "was actually measured")
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              blindness: blind(2, fresh: ["personal", "team"])),
                       .nowhereToGo(.noFreshReading),
                       "and with every candidate unmeasured there is nowhere measured to go")
    }

    func testAMeasuredLimitIsAnsweredBeforeAMissingMeasurement() {
        XCTAssertEqual(decide(reading(session: 95, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .fire(to: "personal", limit: .session, resetsAt: resetsAt),
                       "both are true at once; a limit is a measured fact and blindness is the "
                           + "absence of one, so the journal and the banner name the measured one")
    }

    func testTheMarginIsInclusiveAndTenPointsWide() {
        let onTheEdge = decide(reading(session: 80, weekly: 0), policy: armed,
                               readings: ["personal": reading(session: 0, weekly: 0)],
                               blindness: blind(2, fresh: ["personal"]))
        XCTAssertEqual(onTheEdge,
                       .fireBlind(to: "personal", lastSeen: LastLiveWindow(limit: .session, percent: 80)),
                       "80 is exactly 90 minus 10, and near is inclusive everywhere else in this "
                           + "house, so it is inclusive here")
        XCTAssertEqual(decide(reading(session: 79, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .hold,
                       "a point further away is a hat with room, and a hat with room is never "
                           + "taken off")
        XCTAssertEqual(decide(reading(session: 5, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(3, fresh: ["personal"])),
                       .hold,
                       "a stale five percent is still five percent; the person is told nothing and "
                           + "nothing moves")
    }

    func testEachWindowIsMeasuredAgainstItsOwnThresholdAndAnEmptyThresholdIsSilence() {
        XCTAssertEqual(decide(reading(session: 40, weekly: 88), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .fireBlind(to: "personal", lastSeen: LastLiveWindow(limit: .weekly, percent: 88)),
                       "88 against a weekly threshold of 95 is near even though 40 against 90 is "
                           + "nowhere close, and the notification has to name the week or 88 reads "
                           + "as the five-hour figure")

        var silent = armed
        silent.sessionThresholdPercent = nil
        silent.weeklyThresholdPercent = nil
        XCTAssertEqual(decide(reading(session: 89, weekly: 94), policy: silent,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .hold,
                       "an empty threshold is a trigger the person turned off, not a threshold of "
                           + "zero, and two of them mean there is nothing to be near to")

        var weeklyOnly = armed
        weeklyOnly.sessionThresholdPercent = nil
        XCTAssertEqual(decide(reading(session: 100, weekly: 10), policy: weeklyOnly,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .hold,
                       "with the five-hour trigger off, a five-hour window at 100 is not a margin "
                           + "to measure from")
    }

    func testTheWindowNamedToThePersonIsTheOneClosestToItsOwnThreshold() {
        XCTAssertEqual(decide(reading(session: 80, weekly: 94), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .fireBlind(to: "personal", lastSeen: LastLiveWindow(limit: .weekly, percent: 94)),
                       "both windows are inside their margins; the week is one point from 95 and "
                           + "the five hours are ten from 90, so naming the five-hour window would "
                           + "tell the person about the slacker of the two")
        XCTAssertEqual(decide(reading(session: 89, weekly: 86), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .fireBlind(to: "personal", lastSeen: LastLiveWindow(limit: .session, percent: 89)),
                       "and the other way round, so the answer follows the distance rather than "
                           + "the order the two are written in")
    }

    func testAWindowThatHasAlreadyResetIsNoLongerANumberToLeaveAHatOver() {
        let after = resetsAt.addingTimeInterval(1)
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"]), at: after),
                       .hold,
                       "89 belonged to a five-hour window that has since run out; after a sleep or "
                           + "a long outage the figure describes a window nobody is in any more, "
                           + "and taking the hat off over it spends a switch against a number that "
                           + "no longer exists")
        XCTAssertEqual(decide(reading(session: 0, weekly: 94), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"]), at: after),
                       .hold,
                       "and the same for the week, each window judged by its own reset")
    }

    func testABlindSwitchRefusesAHatWhoseFastestWindowWasNeverRead() {
        let weeklyOnly = UsageReading(session: nil,
                                      weekly: UsageWindow(used: 0, limit: 100, resetsAt: resetsAt))
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": weeklyOnly],
                              blindness: blind(2, fresh: ["personal"])),
                       .hold,
                       "room is decided by crossedLimit, which skips a window the reading does not "
                           + "carry, so a hat whose five-hour figure was never read counts as free "
                           + "while it may be spent - and the five hours are the window this whole "
                           + "branch exists to stay ahead of")
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .fireBlind(to: "personal", lastSeen: LastLiveWindow(limit: .session, percent: 89)),
                       "a hat measured on that window is still a destination")
    }

    func testAWindowTheReadingDoesNotCarryIsNothingToCompareWith() {
        let weeklyOnly = UsageReading(session: nil,
                                      weekly: UsageWindow(used: 88, limit: 100, resetsAt: resetsAt))
        XCTAssertEqual(decide(weeklyOnly, policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .fireBlind(to: "personal", lastSeen: LastLiveWindow(limit: .weekly, percent: 88)),
                       "one window in the reading is measured against its own threshold and the "
                           + "missing one is skipped")

        var sessionOnly = armed
        sessionOnly.weeklyThresholdPercent = nil
        XCTAssertEqual(decide(weeklyOnly, policy: sessionOnly,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .hold,
                       "a threshold with no window to hold it up compares with nothing")
    }

    func testAThresholdSmallerThanTheMarginNeverSwapsZeroForZero() {
        var low = armed
        low.sessionThresholdPercent = 5
        low.weeklyThresholdPercent = nil
        XCTAssertEqual(decide(reading(session: 0, weekly: 0), policy: low,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .hold,
                       "the edge of near never drops below zero, and whatever the worn hat counts "
                           + "as, the target is measured by the very same margin - which is what "
                           + "stops a hat at zero being traded for a hat at zero every two failed "
                           + "polls")
    }

    func testBlindnessIsSwitchedOffWithTheSwitchItself() {
        var off = armed
        off.isOn = false
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: off,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"])),
                       .hold,
                       "the branch sits under the same guard as everything else the policy does")
    }

    func testAHatIsNeverTakenOffBlindBeforeItHasBeenReadOnce() {
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"], read: false)),
                       .hold,
                       "the number belongs to the hat, but it was read before the person put this "
                           + "one on; taking them off a hat they chose a minute ago, on a figure "
                           + "from before they chose it, is what happened on 2026-09-21 at 10:05")
    }

    func testTheBlindBranchOnlyActsOnAPollThatLanded() {
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(2, fresh: ["personal"], landed: false)),
                       .hold,
                       "opening the popover and flicking the toggle inherit a count collected by "
                           + "the polling, which runs whether the switch is on or not - acting on "
                           + "it there would move the person in the same second they opened it")
    }

    func testTheStepItselfIsCountedInPollsAndNeverInSeconds() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/UsageBlindness.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let blindness = try XCTUnwrap(text.components(separatedBy: "struct UsageBlindness").last)
            .components(separatedBy: "static func of(")[0]

        XCTAssertFalse(blindness.contains("Date"),
                       "this is the answer to \"the machine was asleep\": what decides whether to "
                           + "warn or to switch carries a count of polls and no clock, so time "
                           + "passing cannot advance it. decide does take a date now, but only to "
                           + "ask whether a window has already reset - a question about the "
                           + "reading, not about the step - and the one place watching the clock "
                           + "for the step is the gap between landings in MissedPolls")
        XCTAssertEqual(decide(reading(session: 89, weekly: 0), policy: armed,
                              readings: ["personal": reading(session: 0, weekly: 0)],
                              blindness: blind(1, fresh: ["personal"]),
                              at: now.addingTimeInterval(7200)),
                       .hold,
                       "two hours with one missed poll is still one missed poll")
    }
}
