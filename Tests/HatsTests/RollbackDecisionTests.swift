import XCTest
@testable import Hats

final class RollbackDecisionTests: XCTestCase {
    private let attempted = Data("incoming".utf8)
    private let previous = Data("previous".utf8)
    private let stranger = Data("someone else's newer login".utf8)

    func testASlotHoldingWhatThisSwitchWroteIsRestored() {
        XCTAssertEqual(RollbackDecision.decide(now: .holding(attempted), attempted: attempted,
                                               liveBefore: previous), .restore)
    }

    func testASlotAlreadyHoldingThePreviousLoginIsRestored() {
        XCTAssertEqual(RollbackDecision.decide(now: .holding(previous), attempted: attempted,
                                               liveBefore: previous), .restore)
    }

    func testAnEmptySlotIsRestored() {
        XCTAssertEqual(RollbackDecision.decide(now: .empty, attempted: attempted,
                                               liveBefore: previous), .restore)
        XCTAssertEqual(RollbackDecision.decide(now: .empty, attempted: attempted,
                                               liveBefore: nil), .restore)
    }

    func testASlotHoldingSomeoneElsesLoginIsLeftAlone() {
        XCTAssertEqual(RollbackDecision.decide(now: .holding(stranger), attempted: attempted,
                                               liveBefore: previous),
                       .leaveForeignCredentialAlone)
    }

    func testASlotHoldingAnythingAtAllIsLeftAloneWhenThereWasNoPreviousLogin() {
        XCTAssertEqual(RollbackDecision.decide(now: .holding(stranger), attempted: attempted,
                                               liveBefore: nil),
                       .leaveForeignCredentialAlone)
    }

    func testASlotThatCouldNotBeReadIsLeftAloneAndSaysSoSeparately() {
        XCTAssertEqual(RollbackDecision.decide(now: .unreadable, attempted: attempted,
                                               liveBefore: previous),
                       .leaveUnreadableSlotAlone)
        XCTAssertNotEqual(RollbackDecision.decide(now: .unreadable, attempted: attempted,
                                                 liveBefore: previous),
                          .leaveForeignCredentialAlone)
    }
}
