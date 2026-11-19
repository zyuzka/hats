import XCTest
@testable import Hats

final class RenewalBackoffTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let interval: TimeInterval = 300

    func testTheWaitDoublesAndThenStops() {
        XCTAssertEqual(RenewalBackoff.pollsToWait(after: 0), 0, "nothing failed, nothing to wait for")
        XCTAssertEqual([1, 2, 3, 4].map(RenewalBackoff.pollsToWait(after:)), [1, 2, 4, 8])
        XCTAssertEqual(RenewalBackoff.pollsToWait(after: 5), 12,
                       "the cap is 12 polls — an hour at the 300-second interval. It is chosen, not "
                           + "measured, and the reason it can be generous is that nothing is lost by "
                           + "waiting: the parked token this would renew is already expired")
        XCTAssertEqual(RenewalBackoff.pollsToWait(after: 40), 12,
                       "and it stops there rather than overflowing the shift")
    }

    func testAHatNobodyHasFailedIsAllowedStraightAway() {
        XCTAssertTrue(RenewalBackoff().allows("work", at: now))
    }

    func testOneFailureHoldsTheHatForExactlyOnePoll() {
        var backoff = RenewalBackoff()
        backoff.failed("work", at: now, pollingEvery: interval)

        XCTAssertFalse(backoff.allows("work", at: now.addingTimeInterval(interval / 2)))
        XCTAssertTrue(backoff.allows("work", at: now.addingTimeInterval(interval - 1)),
                      "the failure is stamped when the poll lands and the next poll starts one interval "
                          + "after the last one started, so it comes a second early - measured 2026-11-15, "
                          + "09:34:13 against a hold until 09:34:14, and the retry waited a second poll")
        XCTAssertTrue(backoff.allows("work", at: now.addingTimeInterval(interval)))
        XCTAssertTrue(backoff.allows("other", at: now), "and it holds one hat, not every hat")
    }

    func testASlowPollStampsItsFailureAtTheMomentItStarted() {
        let hats: AutoSwitchWatch.Hats = [("personal", false)]
        let slots = FakeSlots([Slot.parked("personal"): credential(expiresAt: 4_000_000_000_000)])
        let answered = DispatchSemaphore(value: 0)
        let watch = AutoSwitchWatch(wakes: NotificationCenter())
        watch.interval = 10
        watch.makeWorld = { _ in
            var world = slots.world(now: Date(), liveSlot: nil)
            world.usage = { _ in
                answered.wait()
                return .refused(401)
            }
            return world
        }
        let landed = expectation(description: "the slow poll landed")
        watch.onReadings = { _ in landed.fulfill() }
        watch.start(hats: { hats })
        defer { watch.stop() }
        let started = Date()

        watch.poll(hats)
        let slow = expectation(description: "the answer takes half a second")
        slow.isInverted = true
        wait(for: [slow], timeout: 0.5)
        answered.signal()
        wait(for: [landed], timeout: 1.0)

        XCTAssertTrue(watch.backoff.allows("personal", at: started.addingTimeInterval(9.2)),
                      "the next poll starts one interval after this one started, not after it landed; "
                          + "a hold stamped at the landing outlasts the early tenth on any poll slower "
                          + "than a tenth of the interval")
        XCTAssertFalse(watch.backoff.allows("personal", at: started.addingTimeInterval(5)))
    }

    func testConsecutiveFailuresStretchTheWait() {
        var backoff = RenewalBackoff()
        backoff.failed("work", at: now, pollingEvery: interval)
        backoff.failed("work", at: now, pollingEvery: interval)

        XCTAssertFalse(backoff.allows("work", at: now.addingTimeInterval(interval)),
                       "the second failure in a row is the whole point: retrying at the poll rate "
                           + "against an endpoint that answered 429 is what earns a longer block")
        XCTAssertTrue(backoff.allows("work", at: now.addingTimeInterval(interval * 2)))
    }

    func testAMintClearsTheHold() {
        var backoff = RenewalBackoff()
        backoff.failed("work", at: now, pollingEvery: interval)
        backoff.failed("work", at: now, pollingEvery: interval)
        backoff.succeeded("work")

        XCTAssertTrue(backoff.allows("work", at: now))
        backoff.failed("work", at: now, pollingEvery: interval)
        XCTAssertTrue(backoff.allows("work", at: now.addingTimeInterval(interval)),
                      "and the count starts again, so one bad hour does not punish the next day")
    }

    func testAHatThatIsGoneStopsBeingRemembered() {
        var backoff = RenewalBackoff()
        backoff.failed("retired", at: now, pollingEvery: interval)
        backoff.keep(["work"])

        XCTAssertTrue(backoff.allows("retired", at: now),
                      "a removed hat leaves nothing behind, and an id can be reused")
    }

    func testOnlyARenewalFailureBacksOffAndAMintClearsIt() {
        var backoff = RenewalBackoff()
        var batch = AutoSwitchWatch.Batch()
        batch.troubles = ["parked": .renewalFailed("http 429"), "worn": .fetchFailed("http 429")]

        AutoSwitchWatch.noteOutcomes(into: &backoff, batch: batch, every: interval, at: now)

        XCTAssertFalse(backoff.allows("parked", at: now))
        XCTAssertTrue(backoff.allows("worn", at: now),
                      "the worn hat's reading failing is not a renewal at all — it never asked the "
                          + "token endpoint, so holding it back would slow a poll for nothing")
    }
}
