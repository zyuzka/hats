import XCTest
@testable import Hats

final class UsageTroubleTests: XCTestCase {
    private let all: [UsageTrouble] = [.nothingStored, .credentialUnreadable, .noTokenStored,
                                       .tokenExpired, .parkedNeedsLogin, .renewalFailed("http 500"),
                                       .fetchFailed("refused 401")]

    func testAnExpiredTokenSaysWhoWillFixItAndWhen() {
        let line = UsageTrouble.tokenExpired.onTheRow
        XCTAssertTrue(line.contains("expired"), line)
        XCTAssertTrue(line.contains("renews it on its next request"),
                      "the blank was read as breakage, so the row has to say the thing that is not broken")
    }

    func testNothingStoredIsNotDescribedAsExpired() {
        let line = UsageTrouble.nothingStored.onTheRow
        XCTAssertTrue(line.contains("nothing is stored"), line)
        XCTAssertFalse(line.contains("expired"),
                       "a hat that was never logged in has no token to have expired")
    }

    func testAFetchFailureKeepsItsOwnReason() {
        XCTAssertTrue(UsageTrouble.fetchFailed("refused 401").onTheRow.contains("refused 401"),
                      "the reason came from the network and is the only thing that identifies it")
    }

    func testEveryReasonSaysTheLimitsAreUnknownRatherThanZero() {
        for trouble in all {
            XCTAssertTrue(trouble.onTheRow.hasPrefix("limits unknown"),
                          "\(trouble): absent limits must not read as low limits")
        }
    }

    func testTheJournalKeepsTheShortFormItAlreadyHad() {
        XCTAssertEqual(UsageTrouble.nothingStored.journalLine, "no credential")
        XCTAssertEqual(UsageTrouble.tokenExpired.journalLine, "no usable token")
        XCTAssertEqual(UsageTrouble.fetchFailed("unreachable").journalLine, "unreachable",
                       "the switch journal has these strings in its history and they should stay greppable")
    }

    func testTheRowTextAndTheJournalTextAreNotTheSameThing() {
        for trouble in all {
            XCTAssertNotEqual(trouble.onTheRow, trouble.journalLine,
                              "\(trouble): the journal is for us and the row is for a person")
        }
    }

    func testAMeterReadingWithoutAReadingFallsBackToTheJournalForm() {
        let now = Date()
        let meters = MeterReading.of(nil, readAt: nil, trouble: .tokenExpired, now: now)
        XCTAssertEqual(meters.line, "no usable token",
                       "the switch journal line is unchanged by giving the reason a type")
    }

    func testEachCauseSaysSomethingDifferentAndOnlyOnePromisesARenewal() {
        let rows = all.map(\.onTheRow)
        XCTAssertEqual(Set(rows).count, all.count, "a shared sentence would hide a cause again")
        XCTAssertEqual(Set(all.map(\.journalLine)).count, all.count)

        let renews = rows.filter { $0.contains("renews it on its next request") }
        XCTAssertEqual(renews.count, 1,
                       "only a genuinely expired token self-heals; a credential with no token at "
                           + "all and an unreadable keychain must not promise a renewal that never "
                           + "comes, which is what collapsing them into .tokenExpired did")
        XCTAssertTrue(UsageTrouble.credentialUnreadable.onTheRow.contains("keychain may be locked"))
        XCTAssertTrue(UsageTrouble.noTokenStored.onTheRow.contains("needs logging in again"))
    }

    func testATroubleDropsTheReadingItContradicts() {
        let stale = UsageReading(session: nil, weekly: nil)
        let existing = ["worn": stale, "parked": stale]
        let batch = AutoSwitchWatch.Batch(troubles: ["worn": .tokenExpired])

        let after = AutoSwitchWatch.readingsAfterAPoll(existing,
                                                       keeping: ["worn", "parked"],
                                                       batch: batch)

        XCTAssertNil(after["worn"],
                     "a hat that once polled successfully kept its reading, so the row went on "
                         + "showing a days-old percentage as current and the new sentence never "
                         + "rendered — the fix was inert exactly where it was needed")
        XCTAssertEqual(after["parked"], stale, "and a hat with no trouble keeps what it had")
    }
}
