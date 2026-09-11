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
        at when: Date? = nil
    ) -> AutoSwitchOutcome {
        AutoSwitchEngine.outcome(
            policy: policy,
            world: AutoSwitchWorld(readings: readings, wearing: wearing, eligible: eligible),
            now: when ?? now
        )
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
        XCTAssertEqual(stuck.decision, .nowhereToGo(.session))
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
}
