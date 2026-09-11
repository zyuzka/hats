import XCTest
@testable import Hats

final class AutoSwitchWatchTests: XCTestCase {
    private let reading = UsageReading(session: nil, weekly: nil)
    private let then = Date(timeIntervalSince1970: 1_800_000_000)

    func testAHatThatFailedOnePollKeepsItsLastReadingAndAHatThatLeftLosesIt() {
        let previous = ["work": reading, "personal": reading, "gone": reading]
        let kept = previous.kept(for: ["work", "personal"]).merging(["work": reading]) { _, new in new }
        XCTAssertEqual(Set(kept.keys), ["work", "personal"],
                       "a blip on personal keeps yesterday's number; a hat no longer in the list is dropped")
    }

    func testEachHatKeepsTheTimeOfItsOwnReading() {
        let previous = ["work": then, "personal": then]
        let now = then.addingTimeInterval(300)
        let stamped = previous.kept(for: ["work", "personal"])
            .merging(AutoSwitchWatch.stamps(for: ["work"], at: now)) { _, new in new }
        XCTAssertEqual(stamped["work"], now)
        XCTAssertEqual(stamped["personal"], then, "a reading carried over keeps its date, so usageAge stays true")
    }

    func testTheShapeOfAPollIsWhichHatsAndWhoWearsWhat() {
        let before: AutoSwitchWatch.Hats = [("work", true), ("personal", false)]
        XCTAssertEqual(AutoSwitchWatch.shape(before), AutoSwitchWatch.shape([("work", true), ("personal", false)]))
        XCTAssertNotEqual(AutoSwitchWatch.shape(before), AutoSwitchWatch.shape([("work", false), ("personal", true)]),
                          "a switch during the poll changes which slot each hat was read from, so the batch is stale")
        XCTAssertNotEqual(AutoSwitchWatch.shape(before), AutoSwitchWatch.shape([("work", true)]))
    }

    func testARiseIsMeasuredFromTheReadingTakenWhileParkedAndForgottenOnWearing() {
        func at(_ percent: Int) -> UsageReading {
            UsageReading(session: UsageWindow(used: percent, limit: 100, resetsAt: nil), weekly: nil)
        }
        func poll(_ readings: [String: UsageReading], worn: Set<String> = [],
                  ids: Set<String> = ["work", "personal"]) -> PollObservation {
            PollObservation(readings: readings, fresh: Set(readings.keys), worn: worn, ids: ids)
        }
        let now = then

        let first = ParkedRises().settled(
            after: poll(["work": at(60), "personal": at(10)], worn: ["work"]), at: now)
        XCTAssertNil(first.from["work"], "a hat being worn has no parked baseline to measure from")
        XCTAssertEqual(first.from["personal"], ParkedBaseline(percent: 10, at: now))
        XCTAssertEqual(first.rises, [:], "the first parked reading is the baseline, not a rise")

        let second = first.settled(after: poll(["work": at(61), "personal": at(14)]), at: now)
        XCTAssertEqual(second.rises["personal"], 4)
        XCTAssertNil(second.rises["work"])
        XCTAssertEqual(second.from["work"], ParkedBaseline(percent: 61, at: now),
                       "work was worn when 60 was read, so 61 becomes its baseline rather than a rise of "
                           + "1 - measuring from a reading taken while worn would report ordinary use as "
                           + "a rise on the first poll after every switch")

        let third = second.settled(after: poll(["personal": at(16)]), at: now)
        XCTAssertEqual(third.rises["personal"], 6, "the rise accumulates from the baseline, not per poll")
        XCTAssertEqual(third.from["work"], second.from["work"],
                       "a hat that was not re-read keeps what it had")

        let worn = third.settled(after: poll([:], worn: ["personal"]), at: now)
        XCTAssertNil(worn.rises["personal"],
                     "wearing it forgets the verdict, so a stale rise cannot survive a wear cycle")
        XCTAssertNil(worn.from["personal"])

        let reset = second.settled(after: poll(["personal": at(2)]), at: now)
        XCTAssertEqual(reset.from["personal"], ParkedBaseline(percent: 2, at: now),
                       "a window that reset reads as a fall; the baseline moves down rather than "
                           + "under-reporting every later climb")
        XCTAssertNil(reset.rises["personal"])

        let backToBaseline = second.settled(after: poll(["personal": at(10)]), at: now)
        XCTAssertNil(backToBaseline.rises["personal"],
                     "a percent equal to the baseline is a rise of zero, and zero is not a rise - leaving "
                         + "the old verdict standing would draw a rise that has gone")
        XCTAssertEqual(backToBaseline.from["personal"], ParkedBaseline(percent: 10, at: now),
                       "and the baseline it equals is kept rather than re-taken")

        let gone = third.settled(after: poll([:], ids: ["work"]), at: now)
        XCTAssertNil(gone.from["personal"], "a hat no longer in the list is dropped")
        XCTAssertNil(gone.rises["personal"])
    }

}
