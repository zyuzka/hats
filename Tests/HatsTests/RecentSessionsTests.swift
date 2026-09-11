import XCTest
@testable import Hats

final class RecentSessionsTests: XCTestCase {
    private func session(_ pid: Int32) -> Session {
        Session(pid: pid, elapsed: "01:00", isInteractive: true, route: .direct)
    }

    func testASecondAskInsideTheWindowDoesNotSweepAgain() {
        let memory = RecentSessions()
        var sweeps = 0

        let first = SessionDiscovery.everySessionSeenRecently(memory: memory) {
            sweeps += 1
            return [self.session(1)]
        }
        let second = SessionDiscovery.everySessionSeenRecently(memory: memory) {
            sweeps += 1
            return [self.session(2)]
        }

        XCTAssertEqual(first?.map(\.pid), [1])
        XCTAssertEqual(second?.map(\.pid), [1], "the second ask is answered from memory")
        XCTAssertEqual(sweeps, 1,
                       "opening the popover once could run ps four times; that is what this closes")
    }

    func testOutsideTheWindowItSweepsAgain() {
        let memory = RecentSessions()
        var sweeps = 0
        _ = SessionDiscovery.everySessionSeenRecently(within: .zero, memory: memory) {
            sweeps += 1
            return [self.session(1)]
        }
        _ = SessionDiscovery.everySessionSeenRecently(within: .zero, memory: memory) {
            sweeps += 1
            return [self.session(2)]
        }
        XCTAssertEqual(sweeps, 2, "a zero window can remember nothing")
    }

    func testASweepThatFailedIsNotRemembered() {
        let memory = RecentSessions()
        var sweeps = 0

        let failed = SessionDiscovery.everySessionSeenRecently(memory: memory) {
            sweeps += 1
            return nil
        }
        let next = SessionDiscovery.everySessionSeenRecently(memory: memory) {
            sweeps += 1
            return [self.session(7)]
        }

        XCTAssertNil(failed)
        XCTAssertEqual(next?.map(\.pid), [7],
                       "one unreadable process table must not blind the next ask for a whole second")
        XCTAssertEqual(sweeps, 2)
        XCTAssertNil(RecentSessions().value(within: .seconds(1)),
                     "a memory nobody filled answers nothing rather than an empty list")
    }

    func testForgettingEmptiesIt() {
        let memory = RecentSessions()
        memory.keep([session(3)])
        XCTAssertEqual(memory.value(within: .seconds(1))?.map(\.pid), [3])
        memory.forget()
        XCTAssertNil(memory.value(within: .seconds(1)))
    }

    func testAnEmptyTableIsAnAnswerAndIsRemembered() {
        let memory = RecentSessions()
        var sweeps = 0
        _ = SessionDiscovery.everySessionSeenRecently(memory: memory) { sweeps += 1; return [] }
        _ = SessionDiscovery.everySessionSeenRecently(memory: memory) { sweeps += 1; return [] }
        XCTAssertEqual(sweeps, 1,
                       "nobody running is a measurement, unlike a table that could not be read")
    }
}
