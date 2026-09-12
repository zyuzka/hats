import XCTest
@testable import Hats

final class SignInGateTests: XCTestCase {
    private func flow(inFlight: Bool, running: Bool?) -> LoginFlow {
        let world = LoginWatchWorld(
            identity: { .loggedOut },
            slot: { _ in .empty },
            resolvedSlot: { nil },
            isDone: { false },
            signInRunning: { running },
            loginInFlight: { inFlight }
        )

        return LoginFlow(store: AccountStore(osAccount: "gate-test"), world: world)
    }

    func testALiveSignInHoldsTheNextOneBack() {
        XCTAssertFalse(flow(inFlight: true, running: true).canStartALogin(),
                       "two sign-ins at once write the same credential slot, and the second would "
                           + "store whichever finished last under the wrong hat")
    }

    func testAFinishedSignInFreesTheNextOneAtOnce() {
        XCTAssertTrue(flow(inFlight: false, running: false).canStartALogin(),
                      "the watch keeps reading the credential back for another thirty seconds "
                          + "after a sign-in ends, and that grace used to answer this question — "
                          + "which is what a tester measured as the app refusing for half a minute")
    }

    func testAProcessAlreadyGoneWhileTheRunIsNotClosedStillHoldsTheNextOne() {
        XCTAssertFalse(flow(inFlight: true, running: false).canStartALogin(),
                       "terminate() returns before the termination handler has run, so for a "
                           + "moment the process is gone while the run has not been closed and "
                           + "nothing has been stored yet. Asking the duty instead read that gap "
                           + "as .none and would have let a second sign-in in through it")
    }
}
