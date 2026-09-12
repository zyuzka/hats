import XCTest
@testable import Hats

final class UsageRefusalBackoffTests: XCTestCase {
    func testAServerThatRefusesOrRateLimitsEarnsAWait() {
        XCTAssertTrue(UsageFetch.refused(401).needsAWait,
                      "a parked token revoked by a second account's login answers 401 forever, and "
                          + "asking again every five minutes is what turns it into 429")
        XCTAssertTrue(UsageFetch.refused(403).needsAWait)
        XCTAssertTrue(UsageFetch.errored(429).needsAWait,
                      "429 is the server saying exactly this in as many words")
    }

    func testAnAnswerOrAnUnreachableServerDoesNot() {
        XCTAssertFalse(UsageFetch.reading(UsageReading(session: nil, weekly: nil)).needsAWait)
        XCTAssertFalse(UsageFetch.unreachable.needsAWait,
                       "no network is not the server pushing back, and it comes back on its own")
        XCTAssertFalse(UsageFetch.errored(500).needsAWait,
                       "a server fault is not a rate limit; the next poll is the right response")
    }
}

final class PollOutcomeBackoffTests: XCTestCase {
    private let interval: TimeInterval = 300
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testARefusedUsageReadSlowsTheNextPollDown() {
        var backoff = RenewalBackoff()
        var batch = UsagePollBatch()
        batch.record(.refused(401), for: "hat", isWearing: false)

        AutoSwitchWatch.noteOutcomes(into: &backoff, batch: batch, every: interval, at: now)

        XCTAssertFalse(backoff.allows("hat", at: now.addingTimeInterval(1)),
                       "before this the only thing that earned a wait was a failed renewal, so a "
                           + "hat whose token the server refuses was asked again every five "
                           + "minutes — measured on a live machine: 401 from 15:09, then 429 for "
                           + "the next three hours")
        XCTAssertTrue(backoff.allows("hat", at: now.addingTimeInterval(interval)),
                      "one refusal costs one poll, no more: a token that comes back must not sit "
                          + "out an hour for a single bad answer")
    }

    func testRefusalsInARowBackOffFurther() {
        var backoff = RenewalBackoff()
        var batch = UsagePollBatch()
        batch.record(.errored(429), for: "hat", isWearing: false)

        AutoSwitchWatch.noteOutcomes(into: &backoff, batch: batch, every: interval, at: now)
        AutoSwitchWatch.noteOutcomes(into: &backoff, batch: batch, every: interval,
                                     at: now.addingTimeInterval(interval))

        XCTAssertFalse(backoff.allows("hat", at: now.addingTimeInterval(interval * 2)),
                       "the second refusal has to cost more than the first, or a dead token keeps "
                           + "its five-minute cadence forever")
    }

    func testAReadingClearsTheWait() {
        var backoff = RenewalBackoff()
        var refused = UsagePollBatch()
        refused.record(.refused(401), for: "hat", isWearing: false)
        AutoSwitchWatch.noteOutcomes(into: &backoff, batch: refused, every: interval, at: now)

        var fine = UsagePollBatch()
        fine.record(.reading(UsageReading(session: nil, weekly: nil)), for: "hat", isWearing: false)
        AutoSwitchWatch.noteOutcomes(into: &backoff, batch: fine, every: interval, at: now)

        XCTAssertTrue(backoff.allows("hat", at: now),
                      "once the account answers again the hat goes back to the ordinary cadence")
    }
}
