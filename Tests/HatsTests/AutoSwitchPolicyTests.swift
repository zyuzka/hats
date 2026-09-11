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
        readings: [String: UsageReading] = [:]
    ) -> AutoSwitchDecision {
        policy.decide(reading: reading, wearing: wearing, eligible: eligible, readings: readings)
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
                              eligible: ["work"]), .nowhereToGo(.session),
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
                       .nowhereToGo(.session))
        XCTAssertEqual(decide(reading(session: 5, weekly: 96), policy: armed,
                              readings: ["work": reading(session: 5, weekly: 96),
                                         "personal": reading(session: 5, weekly: 96),
                                         "team": reading(session: 5, weekly: 96)]),
                       .nowhereToGo(.weekly),
                       "which limit stranded us is the thing worth knowing, and it used to be a "
                           + "silent hold indistinguishable from being below every threshold")
    }
}
