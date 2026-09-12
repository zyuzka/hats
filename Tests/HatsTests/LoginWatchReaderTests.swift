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
            signInRunning: { w.note("signInRunning"); return nil },
            loginInFlight: { w.note("loginInFlight"); return false }
        )
    }

    private static let readers = ["identity", "slot", "resolvedSlot", "isDone", "signInRunning", "loginInFlight"]

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
        XCTAssertNil(seen?.signInRunning)
        XCTAssertEqual(seen?.loginInFlight, false)
    }

}
