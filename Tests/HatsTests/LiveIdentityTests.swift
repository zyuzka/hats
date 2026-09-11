import XCTest
@testable import Hats

final class LiveIdentityTests: XCTestCase {
    func testOnlyAnAccountReadingThatDiffersFromTheScreenIsWorthRedrawing() {
        XCTAssertTrue(LiveIdentity.account("b@x.co").isASettledChange(from: .account("a@x.co")))
        XCTAssertTrue(LiveIdentity.account("b@x.co").isASettledChange(from: .unreadable))
        XCTAssertTrue(LiveIdentity.account("b@x.co").isASettledChange(from: .loggedOut))
        XCTAssertFalse(LiveIdentity.account("a@x.co").isASettledChange(from: .account("a@x.co")))
        XCTAssertFalse(LiveIdentity.account("A@X.co").isASettledChange(from: .account("a@x.co")))
    }

    func testATransientUnreadableOrLoggedOutReadingIsNotDrawnOverAnAccount() {
        XCTAssertFalse(LiveIdentity.unreadable.isASettledChange(from: .account("a@x.co")))
        XCTAssertFalse(LiveIdentity.loggedOut.isASettledChange(from: .account("a@x.co")))
        XCTAssertFalse(LiveIdentity.unreadable.isASettledChange(from: .loggedOut))
    }

    private func status(loggedIn: Bool, email: String?) -> CLI.Status {
        CLI.Status(loggedIn: loggedIn, email: email, orgName: nil,
                   subscriptionType: nil, authMethod: nil)
    }

    func testAStatusThatCouldNotBeReadIsUnreadableRatherThanLoggedOut() {
        XCTAssertEqual(LiveIdentity(status: nil), .unreadable)
    }

    func testAStatusSayingNotLoggedInIsLoggedOut() {
        XCTAssertEqual(LiveIdentity(status: status(loggedIn: false, email: nil)), .loggedOut)
    }

    func testALoggedInStatusWithNoAddressIsUnreadableRatherThanLoggedOut() {
        XCTAssertEqual(LiveIdentity(status: status(loggedIn: true, email: nil)), .unreadable)
        XCTAssertEqual(LiveIdentity(status: status(loggedIn: true, email: "")), .unreadable)
    }

    func testAnAddressOfNothingButSpacesIsNotAnAccount() {
        XCTAssertEqual(LiveIdentity(status: status(loggedIn: true, email: "   ")), .unreadable)
        XCTAssertEqual(LiveIdentity(status: status(loggedIn: true, email: "\n\t")), .unreadable)
    }

    func testAnAddressWithSpaceAroundItIsTheAddressWithoutIt() {
        XCTAssertEqual(LiveIdentity(status: status(loggedIn: true, email: "  A@b.co\n")),
                       .account("A@b.co"))
    }

    func testALoggedInStatusWithAnAddressIsThatAccount() {
        XCTAssertEqual(LiveIdentity(status: status(loggedIn: true, email: "a@b.co")),
                       .account("a@b.co"))
    }

    func testAnUnreadableStateDoesNotClaimNobodyIsLoggedIn() {
        XCTAssertNotEqual(LiveIdentity.unreadable.display, LiveIdentity.loggedOut.display)
        XCTAssertEqual(LiveIdentity.account("a@b.co").display, "a@b.co")
    }

    func testAnUnknownPreviousIdentityIsNotProofTheLiveLoginMoved() {
        XCTAssertFalse(LiveIdentity.account("old@b.co").hasLiveLoginMoved(since: .unreadable))
    }

    func testTheSameAccountLoggingInAgainIsNotTheLiveLoginMoving() {
        XCTAssertFalse(LiveIdentity.account("old@b.co").hasLiveLoginMoved(since: .account("old@b.co")))
        XCTAssertFalse(LiveIdentity.account("Old@B.co ").hasLiveLoginMoved(since: .account("old@b.co")))
    }

    func testAnotherAccountBeingLiveIsTheLiveLoginMoving() {
        XCTAssertTrue(LiveIdentity.account("new@b.co").hasLiveLoginMoved(since: .account("old@b.co")))
    }

    func testAnybodyLoggingInCountsWhenNobodyWasLoggedInBefore() {
        XCTAssertTrue(LiveIdentity.account("new@b.co").hasLiveLoginMoved(since: .loggedOut))
    }

    func testAStateWithNobodyOrNoAnswerIsNotTheLiveLoginMoving() {
        XCTAssertFalse(LiveIdentity.loggedOut.hasLiveLoginMoved(since: .account("old@b.co")))
        XCTAssertFalse(LiveIdentity.unreadable.hasLiveLoginMoved(since: .account("old@b.co")))
    }
}
