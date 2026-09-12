import AppKit
import XCTest
@testable import Hats

final class SignInInFlightChoiceTests: XCTestCase {
    func testTheTwoWaysOutAreTheFirstTwoButtons() {
        XCTAssertEqual(SignInInFlightChoice.of(.alertFirstButtonReturn), .showTheWindow)
        XCTAssertEqual(SignInInFlightChoice.of(.alertSecondButtonReturn), .abandonIt,
                       "a person who cannot find the window has to be able to drop that sign-in, "
                           + "or the app is a wall — which is how the second account became "
                           + "impossible to add")
    }

    func testAnythingElseLeavesTheSignInAlone() {
        XCTAssertEqual(SignInInFlightChoice.of(.alertThirdButtonReturn), .leaveItAlone)
        XCTAssertEqual(SignInInFlightChoice.of(.cancel), .leaveItAlone)
        XCTAssertEqual(SignInInFlightChoice.of(.stop), .leaveItAlone)
    }

    func testTheRefusalSaysWhereTheWindowIsRatherThanHowTheAppIsBuilt() {
        XCTAssertEqual(
            HatsCopy.signInInFlight,
            "Hats runs one sign-in at a time. Its window may be behind other windows, or on "
                + "another desktop."
        )
    }
}

final class AbandoningASignInTests: XCTestCase {
    private func flow(inFlight: Bool) -> LoginFlow {
        let world = LoginWatchWorld(
            identity: { .loggedOut },
            slot: { _ in .empty },
            resolvedSlot: { nil },
            isDone: { false },
            signInRunning: { inFlight },
            loginInFlight: { inFlight }
        )

        return LoginFlow(store: AccountStore(osAccount: "abandon-test"), world: world)
    }

    func testWithNothingToAbandonTheWaitingActionRunsAtOnce() {
        let resumed = expectation(description: "the action the person asked for ran")

        flow(inFlight: false).abandonTheSignIn { resumed.fulfill() }

        wait(for: [resumed], timeout: 2)
    }

}
