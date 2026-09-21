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

    private func landing(_ readings: [String: UsageReading]) -> UsagePollBatch {
        var batch = UsagePollBatch()
        batch.readings = readings
        return batch
    }

    private func watching(_ hats: AutoSwitchWatch.Hats) -> AutoSwitchWatch {
        let watch = AutoSwitchWatch()
        watch.start(hats: { hats })
        return watch
    }

    func testOnlyTheHatsReadInThisPollAreStampedAndOnlyTheirMissesAreForgotten() {
        let hats: AutoSwitchWatch.Hats = [("work", true), ("personal", false)]
        let watch = watching(hats)
        defer { watch.stop() }

        watch.landed(landing(["work": reading, "personal": reading]), polled: hats, from: .timer)
        let read = watch.readAt["work"]
        XCTAssertNotNil(read)
        XCTAssertEqual(watch.missed.count, 0)
        XCTAssertTrue(watch.missed.hasReadTheWornHatSinceItWentOn)

        watch.landed(landing(["personal": reading]), polled: hats, from: .timer)
        XCTAssertEqual(watch.readAt["work"], read,
                       "work was polled and not read, so its stamp is the old one - stamping every "
                           + "hat that was polled rather than every hat that answered is what made "
                           + "usageAge lie, and it is the same mistake the count below would make")
        XCTAssertEqual(watch.missed.count, 1,
                       "and the miss is counted, which is the second place the same mutation can "
                           + "hide: a stamp taken from the polled ids would look fresh while the "
                           + "count still grew, and a count taken from the polled ids would sit at "
                           + "zero while the stamp aged")
        XCTAssertEqual(watch.freshInTheLastPoll, ["personal"])

        watch.landed(landing(["work": reading]), polled: hats, from: .timer)
        XCTAssertEqual(watch.missed.count, 0, "reading it again ends the episode")
        XCTAssertNotEqual(watch.readAt["work"], read)
    }

    func testOnlyTimerPollsOfTheHatBeingWornAreCountedAsMissed() {
        let hats: AutoSwitchWatch.Hats = [("work", true), ("personal", false)]
        let watch = watching(hats)
        defer { watch.stop() }

        watch.landed(landing(["work": reading]), polled: hats, from: .timer)
        watch.landed(landing([:]), polled: hats, from: .outOfBand)
        XCTAssertEqual(watch.missed.count, 0,
                       "a poll fired by a sign-in, a wear or a switch arrives seconds after the "
                           + "last one, so counting it would spend both steps in a couple of seconds")
        watch.landed(landing(["personal": reading]), polled: hats, from: .timer)
        XCTAssertEqual(watch.missed.count, 1,
                       "another hat answering says nothing about the one being worn")
        watch.landed(landing([:]), polled: hats, from: .timer)
        XCTAssertEqual(watch.missed.count, 2)
    }

    func testAHatJustPutOnIsNotBlindUntilItHasBeenReadOnce() {
        let before: AutoSwitchWatch.Hats = [("work", true), ("personal", false)]
        let after: AutoSwitchWatch.Hats = [("work", false), ("personal", true)]
        let watch = watching(before)
        defer { watch.stop() }

        watch.landed(landing(["work": reading]), polled: before, from: .timer)
        watch.landed(landing([:]), polled: before, from: .timer)
        XCTAssertEqual(watch.missed.count, 1)

        watch.stop()
        watch.start(hats: { after })
        watch.landed(landing([:]), polled: after, from: .outOfBand)
        XCTAssertEqual(watch.missed.count, 0,
                       "putting a hat on by hand ends in a poll of its own, and with the network "
                           + "down that poll fails - counting it would start the clock on a hat "
                           + "the person chose a second ago")
        watch.landed(landing([:]), polled: after, from: .timer)
        watch.landed(landing([:]), polled: after, from: .timer)
        XCTAssertEqual(watch.missed.count, 2,
                       "two scheduled checks did miss it, which is the step at which a switch "
                           + "would otherwise happen")
        XCTAssertFalse(watch.missed.hasReadTheWornHatSinceItWentOn,
                       "and still nothing has been read off this hat since it went on, so a stale "
                           + "number belonging to it cannot be a reason to take it off again - "
                           + "one missed poll could not prove this, because the step is two and "
                           + "the criterion would be green with the protection switched off")
    }

    func testAGapMuchLongerThanThePeriodMeansTheAppWasNotRunningRatherThanAMissedCheck() {
        var missed = MissedPolls()
        missed = missed.settled(wearing: "work", fresh: ["work"], from: .timer, every: 300, at: then)
        missed = missed.settled(wearing: "work", fresh: [], from: .timer, every: 300,
                                at: then.addingTimeInterval(300))
        XCTAssertEqual(missed.count, 1)

        let awake = missed.settled(wearing: "work", fresh: [], from: .timer, every: 300,
                                   at: then.addingTimeInterval(300 + 7200))
        XCTAssertEqual(awake.count, 0,
                       "after a sleep the timer fires once and never catches up, so one miss before "
                           + "the sleep and one after would read as two checks missed in ten minutes "
                           + "when the app simply was not running")

        let ordinary = missed.settled(wearing: "work", fresh: [], from: .timer, every: 300,
                                      at: then.addingTimeInterval(300 + 590))
        XCTAssertEqual(ordinary.count, 2,
                       "a late poll inside the slack is still a poll that landed and found nothing")
    }

    func testTurningAutoSwitchOnForgetsWhatWasMissedWhileItWasOff() {
        var missed = MissedPolls()
        missed = missed.settled(wearing: "work", fresh: ["work"], from: .timer, every: 300, at: then)
        missed = missed.settled(wearing: "work", fresh: [], from: .timer, every: 300,
                                at: then.addingTimeInterval(300))
        missed = missed.settled(wearing: "work", fresh: [], from: .timer, every: 300,
                                at: then.addingTimeInterval(600))
        XCTAssertEqual(missed.count, 2)
        missed.forget()
        XCTAssertEqual(missed.count, 0,
                       "polling runs whether the switch is on or not, so a person turning it on "
                           + "would otherwise be moved in the same second by blindness collected "
                           + "while it was off")
        XCTAssertTrue(missed.hasReadTheWornHatSinceItWentOn,
                      "the hat has still been read at some point, and the toggle does not unread it")
    }

    func testWithNoHatOnThereIsNoMissToCount() {
        var missed = MissedPolls()
        missed = missed.settled(wearing: nil, fresh: [], from: .timer, every: 300, at: then)
        missed = missed.settled(wearing: nil, fresh: [], from: .timer, every: 300,
                                at: then.addingTimeInterval(300))
        XCTAssertEqual(missed.count, 0, "a poll that read nothing off nobody is not a miss")
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
