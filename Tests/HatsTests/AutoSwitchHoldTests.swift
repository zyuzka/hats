import XCTest
@testable import Hats

final class AutoSwitchHoldTests: XCTestCase {
    private var policy = AutoSwitchPolicy()

    private func reading(session: Int) -> UsageReading {
        UsageReading(session: UsageWindow(used: session, limit: 100, resetsAt: nil), weekly: nil)
    }

    private func world(wearing: String?, readings: [String: UsageReading] = [:]) -> AutoSwitchWorld {
        AutoSwitchWorld(readings: readings, wearing: wearing, eligible: ["work", "personal"])
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
    }

    func testHoldingIsJournalledOnlyWhereTheDecisionIsHold() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/AppDelegate+AutoSwitch.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        XCTAssertTrue(text.contains("noteHolding(AutoSwitchEngine.reasonForHolding("),
                      "without this the hold branch returns in silence, which is what made "
                          + "\"auto-switch did nothing\" indistinguishable from \"auto-switch chose "
                          + "to wait\" and cost a source read to answer")
        XCTAssertTrue(text.contains("guard lastAutoSwitchHold != reason else { return }"),
                      "and it writes on a change, not on every poll — a line every 300 seconds "
                          + "would refill the log this project already truncated once")
    }
}
