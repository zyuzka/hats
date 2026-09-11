import XCTest
@testable import Hats

final class WatchGenerationTests: XCTestCase {
    func testALateAnswerForASupersededWatchLeavesTheNewerWatchOnDuty() {
        var generations = WatchGeneration()
        let first = generations.take()
        let second = generations.take()

        generations.standDown(first)

        XCTAssertTrue(generations.isOnDuty(second),
                      "a close-window answer arriving for the first watch cleared the duty of the "
                          + "second, which was still in flight, so its poll stopped one tick later")
    }

    func testTheHolderStandsDownWhenTheAnswerIsItsOwn() {
        var generations = WatchGeneration()
        let only = generations.take()

        generations.standDown(only)

        XCTAssertFalse(generations.isOnDuty(only))
    }

    func testStoppingThePollOfASupersededWatchLeavesTheNewerPollAlive() {
        var generations = WatchGeneration()
        let first = generations.take()
        let second = generations.take()

        generations.stopPolling(first)

        XCTAssertEqual(generations.pollHolder, second)
    }

    func testOnlyTheNewestGenerationIsTheCurrentOne() {
        var generations = WatchGeneration()
        let first = generations.take()
        let second = generations.take()

        XCTAssertFalse(generations.isTheCurrent(first))
        XCTAssertTrue(generations.isTheCurrent(second))
    }

    func testTakingAGenerationPutsItOnDutyAndOnThePoll() {
        var generations = WatchGeneration()
        let taken = generations.take()

        XCTAssertEqual(generations.dutyHolder, taken)
        XCTAssertEqual(generations.pollHolder, taken)
    }
}
