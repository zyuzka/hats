import XCTest
@testable import Hats

final class UsageObservationTests: XCTestCase {
    private let both: Set<String> = ["work", "personal"]

    func testATroubleThatHasNotChangedWritesNothing() {
        let standing = ["work": UsageTrouble.fetchFailed("http 429")]

        XCTAssertEqual(UsageObservation.changes(from: standing, to: standing, polled: both), [],
                       "the poll runs every 300 seconds and Journal.log truncates the file to its "
                           + "last 500 lines once it passes 200 KB, so a line per poll would evict "
                           + "the switch history this file exists for. Only the transitions are "
                           + "written, and a duration follows from two of them")
    }

    func testATroubleAppearingIsWrittenWithItsReason() {
        let changes = UsageObservation.changes(
            from: [:],
            to: ["work": .fetchFailed("http 429")],
            polled: both
        )

        XCTAssertEqual(changes, [.init(id: "work", reason: "http 429", previously: nil)])
        XCTAssertEqual(changes.first?.journalEvent, "usage.trouble")
        XCTAssertEqual(changes.first?.details, ["hat": "work", "reason": "http 429"])
    }

    func testATroubleClearingIsWrittenWithWhatItWas() {
        let changes = UsageObservation.changes(
            from: ["work": .fetchFailed("http 429")],
            to: [:],
            polled: both
        )

        XCTAssertEqual(changes, [.init(id: "work", reason: nil, previously: "http 429")])
        XCTAssertEqual(changes.first?.journalEvent, "usage.cleared",
                       "a reading arriving again is the other end of the interval, and without it "
                           + "the journal says when a refusal began and never when it stopped")
        XCTAssertEqual(changes.first?.details, ["hat": "work", "previously": "http 429"])
    }

    func testOneTroubleReplacingAnotherCarriesBoth() {
        let changes = UsageObservation.changes(
            from: ["work": .fetchFailed("http 429")],
            to: ["work": .parkedNeedsLogin],
            polled: both
        )

        XCTAssertEqual(changes.first?.journalEvent, "usage.trouble")
        XCTAssertEqual(changes.first?.details,
                       ["hat": "work",
                        "previously": "http 429",
                        "reason": "parked login cannot be renewed"],
                       "429 giving way to a refused grant is the whole question this event exists "
                           + "to answer, so a bare state name would lose it")
    }

    func testAHatThatWasNotPolledIsNotReportedOnAtAll() {
        let changes = UsageObservation.changes(
            from: ["retired": .fetchFailed("http 429")],
            to: [:],
            polled: ["work"]
        )

        XCTAssertEqual(changes, [],
                       "a hat deleted between two polls loses its trouble because the dictionary is "
                           + "kept for the polled ids, and calling that a recovery would invent one")
    }

    func testEveryPolledHatIsReportedAndTheOrderIsStable() {
        let changes = UsageObservation.changes(
            from: [:],
            to: ["work": .fetchFailed("http 429"), "personal": .parkedNeedsLogin],
            polled: both
        )

        XCTAssertEqual(changes.map(\.id), ["personal", "work"],
                       "a set has no order, so the ids are sorted before they are written — "
                           + "otherwise two polls in the same state produce differently ordered runs")
    }

    func testTheTwoEventNamesAreDistinctAndGreppable() {
        let began = UsageObservation.Change(id: "work", reason: "http 429", previously: nil)
        let ended = UsageObservation.Change(id: "work", reason: nil, previously: "http 429")

        XCTAssertNotEqual(began.journalEvent, ended.journalEvent)
        XCTAssertTrue(began.journalEvent.hasPrefix("usage."))
        XCTAssertTrue(ended.journalEvent.hasPrefix("usage."))
    }
}
