import XCTest
@testable import Hats

final class LoginWatchTests: XCTestCase {
    private let old = "old@b.co"
    private let new = "new@b.co"

    private func watch(expecting: String?, before: LiveIdentity) -> LoginWatch {
        LoginWatch(expecting: expecting, identityBefore: before)
    }

    func testALoginForAnotherAccountIsNotCompleteWhileTheStatusStillNamesTheOldOne() {
        let watching = watch(expecting: new, before: .account(old))
        XCTAssertFalse(watching.hasCompleted(identityNow: .account(old),
                                                        credentialMoved: true))
    }

    func testALoginForAnotherAccountIsCompleteWhenTheStatusNamesIt() {
        let watching = watch(expecting: new, before: .account(old))
        XCTAssertTrue(watching.hasCompleted(identityNow: .account("New@B.co"),
                                                      credentialMoved: false))
    }

    func testAnUnreadableStatusDoesNotCompleteALoginForAnotherAccount() {
        let watching = watch(expecting: new, before: .account(old))
        XCTAssertFalse(watching.hasCompleted(identityNow: .unreadable,
                                                       credentialMoved: true))
    }

    func testAReLoginOfTheLiveAccountWaitsForTheCredentialToMove() {
        let watching = watch(expecting: old, before: .account(old))
        XCTAssertFalse(watching.hasCompleted(identityNow: .account(old),
                                                        credentialMoved: false))
        XCTAssertTrue(watching.hasCompleted(identityNow: .account(old),
                                                       credentialMoved: true))
    }

    func testAnUnreadablePreLoginStatusNeedsTheCredentialToMoveAsWell() {
        let watching = watch(expecting: new, before: .unreadable)
        XCTAssertFalse(watching.hasCompleted(identityNow: .account(new),
                                                        credentialMoved: false))
        XCTAssertTrue(watching.hasCompleted(identityNow: .account(new),
                                                       credentialMoved: true))
    }

    func testNobodyLoggedInBeforeAlsoNeedsTheCredentialToMove() {
        let watching = watch(expecting: new, before: .loggedOut)
        XCTAssertFalse(watching.hasCompleted(identityNow: .account(new),
                                                        credentialMoved: false))
        XCTAssertTrue(watching.hasCompleted(identityNow: .account(new),
                                                       credentialMoved: true))
    }

    func testTheDeadlineStopsAWatchWhoseWindowIsStillOpen() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let deadline = start.addingTimeInterval(900)
        XCTAssertFalse(WatchExpiry.hasExpired(now: start.addingTimeInterval(899),
                                              deadline: deadline, windowClosedAt: nil))
        XCTAssertTrue(WatchExpiry.hasExpired(now: deadline,
                                             deadline: deadline, windowClosedAt: nil))
    }

    func testAClosedWindowGetsItsGraceEvenAtTheEndOfTheDeadline() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let deadline = start.addingTimeInterval(900)
        let closedLate = deadline.addingTimeInterval(-5)
        XCTAssertFalse(WatchExpiry.hasExpired(now: deadline.addingTimeInterval(20),
                                              deadline: deadline,
                                              windowClosedAt: closedLate))
        XCTAssertTrue(WatchExpiry.hasExpired(now: closedLate.addingTimeInterval(31),
                                             deadline: deadline,
                                             windowClosedAt: closedLate))
    }

    func testOnlyTheExpectedAccountSettlesTheWatch() {
        let watching = watch(expecting: new, before: .account(old))
        XCTAssertTrue(watching.hasSettled(onReconciled: "New@B.co"))
        XCTAssertFalse(watching.hasSettled(onReconciled: old))
    }

    func testWithNoExpectedAddressAnyReconciledAccountSettlesTheWatch() {
        XCTAssertTrue(watch(expecting: nil, before: .account(old)).hasSettled(onReconciled: old))
    }

    func testWithNoExpectedAddressEitherHalfMovingCounts() {
        let watching = watch(expecting: nil, before: .account(old))
        XCTAssertTrue(watching.hasCompleted(identityNow: .account(new),
                                                       credentialMoved: false))
        XCTAssertTrue(watching.hasCompleted(identityNow: .account(old),
                                                       credentialMoved: true))
        XCTAssertFalse(watching.hasCompleted(identityNow: .account(old),
                                                        credentialMoved: false))
    }
}

final class LoginWatchDutyTests: XCTestCase {
    private final class Probe {
        private(set) var asked = 0
        private let answer: Bool?
        init(_ answer: Bool?) { self.answer = answer }
        func read() -> Bool? { asked += 1; return answer }
    }

    private func duty(onDuty: Int,
                      pollAlive: Int,
                      loginInFlight: Bool = false,
                      probe: Probe) -> LoginWatchDuty {
        LoginWatchDuty.of(onDuty: onDuty,
                          pollAlive: pollAlive,
                          loginInFlight: loginInFlight,
                          signInRunning: probe.read())
    }

    func testNoWatchOnDutyAsksNothing() {
        let probe = Probe(true)

        XCTAssertEqual(duty(onDuty: 0, pollAlive: 0, probe: probe), LoginWatchDuty.none)
        XCTAssertEqual(probe.asked, 0)
    }

    func testALiveWatchIsLeftAloneWithoutReadingTheProcessTable() {
        let probe = Probe(false)

        XCTAssertEqual(duty(onDuty: 7, pollAlive: 7, probe: probe), .onDuty)
        XCTAssertEqual(probe.asked, 0)
    }

    func testAStaleWatchWhoseScriptIsGoneIsReleased() {
        let duty = duty(onDuty: 7, pollAlive: 0, probe: Probe(false))

        XCTAssertEqual(duty, .staleAndGone)
        XCTAssertTrue(duty.releasesTheWatch)
        XCTAssertFalse(duty.isOnDuty)
    }

    func testAStaleWatchWhoseScriptStillRunsKeepsTheGuard() {
        let duty = duty(onDuty: 7, pollAlive: 0, probe: Probe(true))

        XCTAssertEqual(duty, .staleButUnclear)
        XCTAssertFalse(duty.releasesTheWatch)
        XCTAssertTrue(duty.isOnDuty)
    }

    func testAnUnreadableProcessTableKeepsTheGuard() {
        let duty = duty(onDuty: 7, pollAlive: 0, probe: Probe(nil))

        XCTAssertEqual(duty, .staleButUnclear)
        XCTAssertFalse(duty.releasesTheWatch)
        XCTAssertTrue(duty.isOnDuty)
    }

    func testOnlyAConfirmedAbsenceCountsAsGone() {
        XCTAssertTrue(LoginWatchDuty.isTheSignInConfirmedGone(false))
        XCTAssertFalse(LoginWatchDuty.isTheSignInConfirmedGone(true))
        XCTAssertFalse(LoginWatchDuty.isTheSignInConfirmedGone(nil))
    }

    func testAReleasedWatchStopsBlockingBothTheLoginAndTheSync() {
        let released = duty(onDuty: 7, pollAlive: 0, probe: Probe(false))
        let held = duty(onDuty: 7, pollAlive: 0, probe: Probe(nil))

        XCTAssertEqual(CredentialClaim.forSync(duty: released), .noWatch)
        XCTAssertEqual(CredentialClaim.forSync(duty: held), .watchInProgress)
    }
}

final class OrphanLoginScriptTests: XCTestCase {
    private final class Probe {
        private(set) var asked = 0
        private let answer: Bool?
        init(_ answer: Bool?) { self.answer = answer }
        func read() -> Bool? { asked += 1; return answer }
    }

    private func duty(loginInFlight: Bool, probe: Probe) -> LoginWatchDuty {
        LoginWatchDuty.of(onDuty: 0,
                          pollAlive: 0,
                          loginInFlight: loginInFlight,
                          signInRunning: probe.read())
    }

    func testTheOrdinaryCaseReadsNoProcessTableAtAll() {
        let probe = Probe(true)

        XCTAssertEqual(duty(loginInFlight: false, probe: probe), LoginWatchDuty.none)
        XCTAssertEqual(probe.asked, 0)
    }

    func testALoginLeftRunningByARestartIsFoundWithoutAGeneration() {
        let duty = duty(loginInFlight: true, probe: Probe(true))

        XCTAssertEqual(duty, .orphanSignIn)
        XCTAssertTrue(duty.isOnDuty)
        XCTAssertFalse(duty.releasesTheWatch)
        XCTAssertEqual(CredentialClaim.forSync(duty: duty), .watchInProgress)
    }

    func testAnUnreadableTableWithNoGenerationIsTreatedAsALoginInFlight() {
        let duty = duty(loginInFlight: true, probe: Probe(nil))

        XCTAssertEqual(duty, .orphanSignIn)
        XCTAssertTrue(duty.isOnDuty)
    }

    func testARunThatEndedBlocksNothing() {
        let duty = duty(loginInFlight: true, probe: Probe(false))

        XCTAssertEqual(duty, LoginWatchDuty.none)
        XCTAssertFalse(duty.isOnDuty)
        XCTAssertEqual(CredentialClaim.forSync(duty: duty), .noWatch)
    }

    func testASignInThatIsNoLongerInFlightIsNotProbedAtAll() {
        let probe = Probe(nil)

        let duty = LoginWatchDuty.of(onDuty: 0, pollAlive: 0,
                                     loginInFlight: false,
                                     signInRunning: probe.read())

        XCTAssertEqual(duty, LoginWatchDuty.none)
        XCTAssertEqual(probe.asked, 0,
                       "the run itself knows whether it has ended, so nothing has to be asked of "
                           + "the operating system to answer this")
        XCTAssertEqual(CredentialClaim.forSync(duty: duty), .noWatch)
    }

    func testASignInSeenRunningAndThenGoneWithoutSucceedingHasDied() {
        XCTAssertTrue(LoginWatchDuty.hasTheSignInDiedWithoutFinishing(
            seenRunning: true, loginInFlight: true, signInRunning: false))
    }

    func testASignInNeverSeenRunningHasNotDiedButNotStartedYet() {
        XCTAssertFalse(LoginWatchDuty.hasTheSignInDiedWithoutFinishing(
            seenRunning: false, loginInFlight: true, signInRunning: false))
    }

    func testAScriptThatWroteItsMarkerHasFinishedNotDied() {
        XCTAssertFalse(LoginWatchDuty.hasTheSignInDiedWithoutFinishing(
            seenRunning: true, loginInFlight: false, signInRunning: false))
    }

    func testOnlyAReadableTableWithoutTheScriptDeclaresItDead() {
        XCTAssertFalse(LoginWatchDuty.hasTheSignInDiedWithoutFinishing(
            seenRunning: true, loginInFlight: true, signInRunning: nil))
        XCTAssertFalse(LoginWatchDuty.hasTheSignInDiedWithoutFinishing(
            seenRunning: true, loginInFlight: true, signInRunning: true))
    }

    func testReleasingTheCountersDoesNotOpenASecondLoginWhileAScriptIsAlive() {
        let alive = LoginWatchDuty.of(onDuty: 0, pollAlive: 0, loginInFlight: true,
                                      signInRunning: true)
        XCTAssertEqual(alive, .orphanSignIn)
        XCTAssertTrue(alive.isOnDuty,
                      "the timeout now releases the counters without waiting for the window close, "
                          + "which is only safe because a genuinely live login script still answers "
                          + "on duty through its own liveness check rather than through the counter")

        let gone = LoginWatchDuty.of(onDuty: 0, pollAlive: 0, loginInFlight: true,
                                     signInRunning: false)
        XCTAssertFalse(gone.isOnDuty, "and a script confirmed gone must not hold the guard")
    }
}
