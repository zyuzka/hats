import XCTest
@testable import Hats

final class AutoSwitchHoldTests: XCTestCase {
    private var policy = AutoSwitchPolicy()

    private func reading(session: Int) -> UsageReading {
        UsageReading(session: UsageWindow(used: session, limit: 100, resetsAt: nil), weekly: nil)
    }

    private func world(
        wearing: String?,
        readings: [String: UsageReading] = [:],
        blindness: UsageBlindness = UsageBlindness()
    ) -> AutoSwitchWorld {
        AutoSwitchWorld(readings: readings, wearing: wearing,
                        eligible: ["work", "personal"], blindness: blindness)
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

    func testASwitchTurnedOffSaysSoRatherThanNothing() {
        policy.isOn = false

        XCTAssertEqual(AutoSwitchEngine.reasonForHolding(policy: policy, world: world(wearing: "work")),
                       .off)
    }

    func testNoHatOnIsItsOwnReason() {
        policy.isOn = true

        XCTAssertEqual(AutoSwitchEngine.reasonForHolding(policy: policy, world: world(wearing: nil)),
                       .noHatOn,
                       "isWearing comes from the identity read off the live credential, not from the "
                           + "stored activeID, so this is reachable whenever that read fails — and it "
                           + "used to look exactly like a switch that decided to wait")
    }

    func testAWornHatWithNoNumberIsToldApartFromOneUnderTheThreshold() {
        policy.isOn = true

        XCTAssertEqual(
            AutoSwitchEngine.reasonForHolding(policy: policy, world: world(wearing: "work")),
            .noReading,
            "no reading at all and a reading that is simply low are different problems: the first "
                + "is a poll that could not read, the second is the app working as asked")
        XCTAssertEqual(
            AutoSwitchEngine.reasonForHolding(
                policy: policy,
                world: world(wearing: "work", readings: ["work": reading(session: 89)])
            ),
            .underTheThresholds)
    }

    func testAThresholdActuallyCrossedIsNotAReasonToHold() {
        policy.isOn = true

        XCTAssertNil(
            AutoSwitchEngine.reasonForHolding(
                policy: policy,
                world: world(wearing: "work", readings: ["work": reading(session: 90)])
            ),
            "the caller asks only after the decision was hold, so a crossed threshold here means "
                + "the two disagree — answering nil says that instead of inventing a reason")
    }

    func testTheReasonsAreWrittenAsThemselves() {
        XCTAssertEqual(AutoSwitchHold.underTheThresholds.rawValue, "underTheThresholds",
                       "the raw value is what lands in the journal, so it is part of the interface "
                           + "a person greps")
        XCTAssertEqual(AutoSwitchHold.blindAndNear.rawValue, "blindAndNear")
        XCTAssertEqual(AutoSwitchHold.blindAndFar.rawValue, "blindAndFar")
        XCTAssertEqual(AutoSwitchHold.blindTargetSpent.rawValue, "blindTargetSpent")
    }

    func testASwitchNobodyTurnedOnDoesNotNarrateItselfIntoTheLog() {
        XCTAssertFalse(AutoSwitchHold.off.isWorthAJournalLine,
                       "the polling runs whether auto-switching is on or not, so somebody who "
                           + "never turned it on would get a line saying so - and the setting is "
                           + "already in settings.json, where it says the same thing once")
        for reason: AutoSwitchHold in [.noHatOn, .noReading, .underTheThresholds,
                                       .blindAndNear, .blindAndFar, .blindTargetSpent] {
            XCTAssertTrue(reason.isWorthAJournalLine, "\(reason) is something that happened")
        }
    }

    func testTheMissedPollCountIsForgottenOnlyWhenTheSwitchIsTurnedOn() {
        var off = AutoSwitchPolicy()
        off.isOn = false
        var on = off
        on.isOn = true

        XCTAssertTrue(on.hasJustBeenTurnedOn(from: off))
        XCTAssertFalse(off.hasJustBeenTurnedOn(from: on), "turning it off forgets nothing")
        var nudged = on
        nudged.sessionThresholdPercent = 85
        XCTAssertFalse(nudged.hasJustBeenTurnedOn(from: on),
                       "the panel calls updateAutoSwitch from four places - a threshold step, the "
                           + "order arrows, the notifications toggle and the switch itself - so "
                           + "keying this on \"the policy changed\" let any fiddling in the "
                           + "settings during an outage push the protection two more polls away")
        XCTAssertFalse(on.hasJustBeenTurnedOn(from: on), "saving the same policy changes nothing")
    }

    func testAStaleNumberIsNeverReportedAsBeingUnderTheThresholds() {
        policy.isOn = true
        let near = ["work": reading(session: 89)]

        XCTAssertEqual(
            AutoSwitchEngine.reasonForHolding(
                policy: policy,
                world: world(wearing: "work", readings: near, blindness: blind(1))
            ),
            .blindAndNear,
            "one missed poll on a number a point under the line: the person is told, and nothing "
                + "moves yet")
        XCTAssertEqual(
            AutoSwitchEngine.reasonForHolding(
                policy: policy,
                world: world(wearing: "work", readings: ["work": reading(session: 5)],
                             blindness: blind(3))
            ),
            .blindAndFar,
            "five percent stays five percent whatever the network does, so the person hears "
                + "nothing - but the number is old, and calling it \"under the thresholds\" would "
                + "say it had just been measured")
        XCTAssertEqual(
            AutoSwitchEngine.reasonForHolding(
                policy: policy,
                world: world(wearing: "work",
                             readings: ["work": reading(session: 89), "personal": reading(session: 97)],
                             blindness: blind(2, fresh: ["personal"]))
            ),
            .blindTargetSpent,
            "the step for switching was reached and what was read in this poll has no room to "
                + "spare, so there is nowhere measured to move")
        XCTAssertNil(
            AutoSwitchEngine.reasonForHolding(
                policy: policy,
                world: world(wearing: "work",
                             readings: ["work": reading(session: 89), "personal": reading(session: 0)],
                             blindness: blind(2, fresh: ["personal"]))
            ),
            "here the switch actually fires, and a reason for holding invented next to it would be "
                + "handed straight to the warning - the person would get \"can't read usage\" and "
                + "\"Switched to …\" within the same instant, the second one contradicting the first")
        XCTAssertEqual(
            AutoSwitchEngine.reasonForHolding(
                policy: policy,
                world: world(wearing: "work", readings: near, blindness: blind(0))
            ),
            .underTheThresholds,
            "no missed poll, no blindness, and the old answer stands untouched")
        XCTAssertEqual(
            AutoSwitchEngine.reasonForHolding(
                policy: policy,
                world: world(wearing: "work", readings: near, blindness: blind(2, read: false))
            ),
            .underTheThresholds,
            "a hat nobody has read since it went on cannot be blind about itself")
    }

    func testHoldingIsJournalledOnlyWhereTheDecisionIsHold() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/AppDelegate+AutoSwitch.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        XCTAssertTrue(text.contains("noteHolding(holding, missedPolls:"),
                      "without this the hold branch returns in silence, which is what made "
                          + "\"auto-switch did nothing\" indistinguishable from \"auto-switch chose "
                          + "to wait\" and cost a source read to answer")
        XCTAssertTrue(text.contains("guard lastAutoSwitchHold != reason else { return }"),
                      "and it writes on a change of reason, not on every poll — a line every 300 "
                          + "seconds would refill the log this project already truncated once, and "
                          + "the missed-poll count only ever climbs, so keying on it would give a "
                          + "long network outage one line every five minutes for as long as it "
                          + "lasted. The numbers still go in the line; they just do not reopen it")
    }
}
