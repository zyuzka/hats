import XCTest
@testable import Hats

final class LoginWatchReaderTests: XCTestCase {
    private final class Where {
        private let lock = NSLock()
        private var onMain: [String: Bool] = [:]

        func note(_ name: String) {
            lock.lock()
            onMain[name] = Thread.isMainThread
            lock.unlock()
        }

        func ranOnMain(_ name: String) -> Bool? {
            lock.lock()
            defer { lock.unlock() }
            return onMain[name]
        }
    }

    private func world(_ w: Where) -> LoginWatchWorld {
        LoginWatchWorld(
            identity: { w.note("identity"); return .loggedOut },
            slot: { named in w.note("slot")
                XCTAssertEqual(named, "Claude Code-credentials-probe")
                return .empty },
            resolvedSlot: { w.note("resolvedSlot"); return nil },
            isDone: { w.note("isDone"); return false },
            scriptRunning: { w.note("scriptRunning"); return nil },
            loginInFlight: { w.note("loginInFlight"); return false },
            closeTheWindow: { w.note("closeTheWindow"); return .couldNotAsk },
            removeScript: { w.note("removeScript") }
        )
    }

    private static let readers = ["identity", "slot", "resolvedSlot", "isDone", "scriptRunning", "loginInFlight"]

    func testEveryReadOfTheWorldLeavesTheMainThread() {
        let w = Where()
        let reader = LoginWatchReader.of(world: world(w))
        let applied = expectation(description: "reading applied")

        reader.read(inSlot: "Claude Code-credentials-probe") { _ in applied.fulfill() }
        wait(for: [applied], timeout: 5)

        for name in Self.readers {
            XCTAssertEqual(w.ranOnMain(name), false,
                           "\(name) is a subprocess or a keychain read and must not run on the main thread")
        }
    }

    func testTheReadingComesBackOnTheMainThread() {
        let w = Where()
        let reader = LoginWatchReader.of(world: world(w))
        let applied = expectation(description: "reading applied")
        var appliedOnMain: Bool?

        reader.read(inSlot: "Claude Code-credentials-probe") { _ in
            appliedOnMain = Thread.isMainThread
            applied.fulfill()
        }
        wait(for: [applied], timeout: 5)

        XCTAssertEqual(appliedOnMain, true,
                       "the reading is applied to state the menu also reads, so it has to arrive on main")
    }

    func testTheReadingCarriesWhatTheWorldAnswered() {
        let w = Where()
        let reader = LoginWatchReader.of(world: world(w))
        let applied = expectation(description: "reading applied")
        var seen: LoginWatchReading?

        reader.read(inSlot: "Claude Code-credentials-probe") { reading in
            seen = reading
            applied.fulfill()
        }
        wait(for: [applied], timeout: 5)

        XCTAssertEqual(seen?.identity, .loggedOut)
        XCTAssertEqual(seen?.slot, .empty)
        XCTAssertEqual(seen?.isDone, false)
        XCTAssertNil(seen?.scriptRunning)
        XCTAssertEqual(seen?.loginInFlight, false)
    }

    func testClosingTheWindowAlsoLeavesTheMainThread() {
        let w = Where()
        let reader = LoginWatchReader.of(world: world(w))
        let reported = expectation(description: "close reported")
        var reportedOnMain: Bool?

        reader.closeTheWindow { _, _ in
            reportedOnMain = Thread.isMainThread
            reported.fulfill()
        }
        wait(for: [reported], timeout: 5)

        XCTAssertEqual(w.ranOnMain("closeTheWindow"), false,
                       "closeLoginWindow runs osascript, which must not block the main thread")
        XCTAssertEqual(w.ranOnMain("scriptRunning"), false)
        XCTAssertEqual(reportedOnMain, true,
                       "the outcome decides whether the watch guard is released, which is main-thread state")
    }

    func testAClosureWithNothingToReportStillCloses() {
        let w = Where()
        let reader = LoginWatchReader.of(world: world(w))
        reader.closeTheWindow(then: nil)

        let settled = expectation(description: "queue drained")
        reader.queue.async { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertEqual(w.ranOnMain("closeTheWindow"), false)
        XCTAssertNil(w.ranOnMain("scriptRunning"),
                     "with nobody to report to there is no reason to spend a second ps read")
    }
}
