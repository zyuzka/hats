import XCTest
@testable import Hats

final class QuitCostTests: XCTestCase {
    private func session(_ pid: Int32) -> Session {
        Session(pid: pid, elapsed: "01:00", isInteractive: true, route: .direct)
    }

    func testNothingRunningAsksNothing() {
        XCTAssertNil(HatsCopy.quitCost(.counted([])),
                     "with no live session quitting costs nothing, so no dialog may stand in the way")
    }

    func testOneSessionIsCountedInTheSingular() {
        let cost = HatsCopy.quitCost(.counted([session(1)]))
        XCTAssertEqual(cost?.hasPrefix("1 live session running."), true, cost ?? "no cost")
    }

    func testSeveralSessionsAreCountedInThePlural() {
        let cost = HatsCopy.quitCost(.counted([session(1), session(2), session(3)]))
        XCTAssertEqual(cost?.hasPrefix("3 live sessions running."), true, cost ?? "no cost")
    }

    func testABatchSessionIsPartOfWhatQuittingCosts() {
        let oneShot = Session(pid: 9, elapsed: "00:20", isInteractive: false, route: .direct)
        let cost = HatsCopy.quitCost(.counted([oneShot]))
        XCTAssertEqual(cost?.hasPrefix("1 live session running."), true,
                       "quitting stops the gateway under a claude -p run too, so it is counted; "
                           + "the caller reads the process table with the dependency reader")
    }

    func testAnUnreadableProcessTableStillAsks() {
        let cost = HatsCopy.quitCost(.unknown)
        XCTAssertNotNil(cost, "an unreadable table is not an answer, so the guard asks rather than quits")
        XCTAssertEqual(cost?.contains("could not be read"), true, cost ?? "no cost")
    }

    func testEveryWarningNamesWhatQuittingStops() {
        for state in [SessionsState.unknown, .counted([session(1)])] {
            XCTAssertEqual(HatsCopy.quitCost(state)?.contains("stops the gateway"), true,
                           "the cost of quitting is the gateway, and the sentence has to say so")
            XCTAssertEqual(HatsCopy.quitCost(state)?.contains("shell"), true,
                           "the install note gives two cures, so the dialog must not promise only Hats coming back")
        }
    }
}
