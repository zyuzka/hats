import XCTest
@testable import Hats

final class SignInSettledTests: XCTestCase {
    private func world() -> LoginWatchWorld {
        LoginWatchWorld(
            identity: { .account("a@b.com") },
            slot: { _ in .holding(Data("the new credential".utf8)) },
            resolvedSlot: { nil },
            isDone: { true },
            signInRunning: { false },
            loginInFlight: { false }
        )
    }

    private func run(_ world: LoginWatchWorld) -> LoginWatchRun {
        LoginWatchRun(
            reader: .of(world: world),
            world: world,
            duty: WatchDutyControl(
                isOnDuty: { _ in true },
                isTheCurrent: { _ in true },
                standDown: { _ in },
                stopPolling: { _ in }
            ),
            generation: 1,
            watch: LoginWatch(expecting: "a@b.com", identityBefore: .loggedOut),
            deadline: Date().addingTimeInterval(60),
            expecting: "a@b.com",
            inSlot: "Claude Code-credentials",
            credentialBefore: .empty,
            pinned: true
        )
    }

    func testASettledSignInIsAnnouncedSoFreshLimitsCanBeRead() {
        let announced = expectation(description: "the settled sign-in was announced")
        let watch = run(world())
        watch.syncWithWorld = { _, _ in "a@b.com" }
        watch.signInSettled = { announced.fulfill() }

        watch.start()

        wait(for: [announced], timeout: 10)
    }

    func testASignInThatSettlesForSomeoneElseIsNotAnnounced() {
        let announced = expectation(description: "announced")
        announced.isInverted = true
        let watch = run(world())
        watch.syncWithWorld = { _, _ in "someone.else@b.com" }
        watch.signInSettled = { announced.fulfill() }

        watch.start()

        wait(for: [announced], timeout: 4)
    }
}
