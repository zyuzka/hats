import XCTest
@testable import Hats

final class DeferredPollSourceTests: XCTestCase {
    func testAPollQueuedBehindARunningOneKeepsTheTimerAsItsSource() {
        let hats: AutoSwitchWatch.Hats = [
            ("work", true),
        ]
        let slots = FakeSlots([:])
        let firstMayFinish = DispatchSemaphore(value: 0)
        var worldsMade = 0
        let watch = AutoSwitchWatch(wakes: NotificationCenter())
        watch.makeWorld = { _ in
            worldsMade += 1
            if worldsMade == 1 { firstMayFinish.wait() }
            return slots.world(now: Date(), liveSlot: nil)
        }
        let bothLanded = expectation(description: "the running poll and the queued one both landed")
        bothLanded.expectedFulfillmentCount = 2
        watch.onReadings = { _ in bothLanded.fulfill() }
        watch.start(hats: { hats })
        defer { watch.stop() }

        watch.poll(hats, from: .outOfBand)
        watch.poll(hats, from: .timer)
        firstMayFinish.signal()
        wait(for: [bothLanded], timeout: 1.5)

        XCTAssertEqual(
            watch.missed.count,
            1,
            "only a timer poll counts a missed reading of the worn hat; the queued poll came "
                + "from the timer, so it must land as one rather than as out of band"
        )
    }
}
