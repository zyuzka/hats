import Sparkle
import XCTest
@testable import Hats

final class SparkleBridgeTests: XCTestCase {
    func testLaterInTheUpdateWindowRedrawsTheMenu() {
        var asked: [String] = []
        let updates = SparkleUpdates(
            decideTheRestart: { .ask("1 live session") },
            confirm: { cost in
                asked.append(cost)
                return false
            },
            notify: { _, _ in XCTFail("nothing here announces an update") }
        )
        let redrawn = expectation(description: "the menu was told to redraw")
        updates.whenCanCheckNowChanges = { redrawn.fulfill() }
        let driver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil)
        let updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: driver,
            delegate: nil
        )
        var installs = 0

        let postponed = updates.updater(
            updater,
            shouldPostponeRelaunchForUpdate: SUAppcastItem.empty(),
            untilInvokingBlock: { installs += 1 }
        )
        wait(for: [redrawn], timeout: 1.0)

        XCTAssertTrue(postponed)
        XCTAssertEqual(
            asked,
            [
                "1 live session",
            ]
        )
        XCTAssertEqual(installs, 0, "Later must not restart Hats")
        XCTAssertTrue(updates.hasAnUpdateWaiting, "and the menu redraws to offer the waiting install")
    }
}
