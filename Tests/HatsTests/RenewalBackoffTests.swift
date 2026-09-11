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

        XCTAssertFalse(backoff.allows("work", at: now.addingTimeInterval(interval - 1)))
        XCTAssertTrue(backoff.allows("work", at: now.addingTimeInterval(interval)),
                      "the deadline itself is allowed, so a poll landing exactly on it is not "
                          + "pushed to the one after")
        XCTAssertTrue(backoff.allows("other", at: now), "and it holds one hat, not every hat")
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

        AutoSwitchWatch.noteRenewalOutcomes(into: &backoff, batch: batch, every: interval, at: now)

        XCTAssertFalse(backoff.allows("parked", at: now))
        XCTAssertTrue(backoff.allows("worn", at: now),
                      "the worn hat's reading failing is not a renewal at all — it never asked the "
                          + "token endpoint, so holding it back would slow a poll for nothing")
    }
}
