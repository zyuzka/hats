import XCTest
@testable import Hats

final class HeaderSightingTests: XCTestCase {
    private static let work = LiveCredential(hat: "work", fingerprint: "abcd1234")
    private static let personal = LiveCredential(hat: "personal", fingerprint: "ffff0000")

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var remembered = PollsOnHeaders()

    private func createWindow(used: Int) -> UsageWindow {
        UsageWindow(
            used: used,
            limit: 100,
            resetsAt: nil
        )
    }

    private func createReading(session: Int?, weekly: Int? = nil) -> UsageReading {
        UsageReading(
            session: session.map(createWindow(used:)),
            weekly: weekly.map(createWindow(used:))
        )
    }

    private func createPolicy(isOn: Bool = true) -> AutoSwitchPolicy {
        var policy = AutoSwitchPolicy()
        policy.isOn = isOn
        policy.sessionThresholdPercent = 85
        policy.weeklyThresholdPercent = 98

        return policy
    }

    private func createWorld(
        isOn: Bool = true,
        wearing: String? = HeaderSightingTests.work.hat,
        live: LiveCredential? = HeaderSightingTests.work,
        polled: UsageReading? = nil,
        interval: TimeInterval = 300
    ) -> HeaderSightingWorld {
        HeaderSightingWorld(
            policy: createPolicy(isOn: isOn),
            wearing: wearing,
            liveCredential: live,
            readings: [
                Self.work.hat: polled ?? createReading(session: 70, weekly: 40),
            ],
            interval: interval
        )
    }

    private func createPolls(pollingAt moment: Date) -> PollsOnHeaders {
        var polls = PollsOnHeaders()
        _ = polls.getDecision(
            credential: Self.work.fingerprint,
            reading: createReading(session: 86),
            world: createWorld(),
            at: moment
        )

        return polls
    }

    private func getDecision(for reading: UsageReading, in world: HeaderSightingWorld) -> HeaderSighting {
        remembered.getDecision(
            credential: Self.work.fingerprint,
            reading: reading,
            world: world,
            at: now
        )
    }

    private func getDecision(
        wearing live: LiveCredential,
        after seconds: TimeInterval,
        interval: TimeInterval = 300
    ) -> HeaderSighting {
        remembered.getDecision(
            credential: live.fingerprint,
            reading: createReading(session: 86),
            world: createWorld(
                wearing: live.hat,
                live: live,
                interval: interval
            ),
            at: now.addingTimeInterval(seconds)
        )
    }

    func testEachReasonComesFromItsOwnInput() {
        let worn = Self.work.fingerprint
        let crossed = createReading(session: 86)
        let weekly = createReading(session: 10, weekly: 98)
        let below = createReading(session: 84, weekly: 50)
        let spent = createReading(session: 90)
        let fresh = PollsOnHeaders()
        let justPolled = createPolls(pollingAt: now.addingTimeInterval(-10))
        let rows: [(String, PollsOnHeaders, String, UsageReading, HeaderSightingWorld, HeaderSighting)] = [
            ("crossed", fresh, worn, crossed, createWorld(), .pollNow),
            ("weekly crossed", fresh, worn, weekly, createWorld(), .pollNow),
            ("another key", fresh, Self.personal.fingerprint, crossed, createWorld(), .anotherCredential),
            ("no key read", fresh, worn, crossed, createWorld(live: nil), .credentialUnknown),
            ("key of another hat", fresh, worn, crossed, createWorld(wearing: Self.personal.hat), .credentialUnknown),
            ("below", fresh, worn, below, createWorld(), .underTheThresholds),
            ("already known", fresh, worn, crossed, createWorld(polled: spent), .alreadyKnown),
            ("too soon", justPolled, worn, crossed, createWorld(), .tooSoon),
            ("switch off", fresh, worn, crossed, createWorld(isOn: false), .autoSwitchIsOff),
        ]
        for (name, prepared, credential, reading, world, expected) in rows {
            var polls = prepared

            let sighting = polls.getDecision(
                credential: credential,
                reading: reading,
                world: world,
                at: now
            )

            XCTAssertEqual(
                sighting,
                expected,
                name
            )
        }
    }

    func testTheOldKeyAfterASwitchIsNotTheCurrentHatsKey() {
        let beforeThePollLands = createWorld(
            wearing: Self.personal.hat,
            live: Self.work
        )

        XCTAssertEqual(
            getDecision(for: createReading(session: 100), in: beforeThePollLands),
            .credentialUnknown,
            "the remembered key was read from the hat taken off, so it does not stand for the hat now worn"
        )
        XCTAssertEqual(
            getDecision(for: createReading(session: 100), in: createWorld(wearing: nil)),
            .credentialUnknown,
            "with no hat on there is no current key to match"
        )
    }

    func testTheSameHatWaitsForTheScheduledIntervalBeforeAnotherPollOnHeaders() {
        XCTAssertEqual(getDecision(wearing: Self.work, after: 0), .pollNow)
        XCTAssertEqual(getDecision(wearing: Self.work, after: 10), .tooSoon)
        XCTAssertEqual(
            getDecision(wearing: Self.work, after: 100),
            .tooSoon,
            "past the shared 30 seconds, but the same hat waits for the scheduled interval"
        )
        XCTAssertEqual(getDecision(wearing: Self.work, after: 300), .pollNow)
    }

    func testTheScheduledIntervalIsTheOneTheWorldCarries() {
        XCTAssertEqual(getDecision(wearing: Self.work, after: 0), .pollNow)
        XCTAssertEqual(
            getDecision(
                wearing: Self.work,
                after: 130,
                interval: 120
            ),
            .pollNow,
            "with a 120-second interval in the world, 130 seconds later the same hat is polled again"
        )
    }

    func testAnotherHatWaitsOnlyForTheSharedThirtySeconds() {
        XCTAssertEqual(getDecision(wearing: Self.work, after: 0), .pollNow)
        XCTAssertEqual(getDecision(wearing: Self.personal, after: 29), .tooSoon)
        XCTAssertEqual(getDecision(wearing: Self.personal, after: 31), .pollNow)
    }

    func testTheSharedQuietPeriodEndsAtExactlyThirtySeconds() {
        XCTAssertEqual(getDecision(wearing: Self.work, after: 0), .pollNow)
        XCTAssertEqual(getDecision(wearing: Self.personal, after: 30), .pollNow)
    }

    func testOnlyAPollIsRememberedAndNoOtherAnswerHoldsTheNextCrossingBack() {
        let worn = Self.work.fingerprint
        let crossed = createReading(session: 86)
        let rows: [(String, String, UsageReading, HeaderSightingWorld, HeaderSighting)] = [
            ("below", worn, createReading(session: 84, weekly: 50), createWorld(), .underTheThresholds),
            ("another key", Self.personal.fingerprint, crossed, createWorld(), .anotherCredential),
            ("already known", worn, crossed, createWorld(polled: createReading(session: 90)), .alreadyKnown),
        ]
        for (name, credential, reading, world, expected) in rows {
            var polls = PollsOnHeaders()

            let first = polls.getDecision(
                credential: credential,
                reading: reading,
                world: world,
                at: now
            )
            let next = polls.getDecision(
                credential: worn,
                reading: crossed,
                world: createWorld(),
                at: now.addingTimeInterval(1)
            )

            XCTAssertEqual(
                first,
                expected,
                name
            )
            XCTAssertEqual(
                next,
                .pollNow,
                "a crossing one second after \"\(name)\" is polled"
            )
        }
    }

    func testAClockThatWentBackDoesNotHoldThePollsBack() {
        XCTAssertEqual(getDecision(wearing: Self.work, after: 0), .pollNow)
        XCTAssertEqual(
            getDecision(wearing: Self.work, after: -60),
            .pollNow,
            "a gap of minus sixty seconds is not too soon"
        )
    }

    func testTwoCrossingsInARowGiveExactlyOnePoll() {
        let sightings = [
            getDecision(wearing: Self.work, after: 0),
            getDecision(wearing: Self.work, after: 0),
        ]

        XCTAssertEqual(sightings.filter { $0 == .pollNow }.count, 1)
    }

    func testAThresholdThatIsSwitchedOffIsNeverCrossedByAHeader() {
        var policy = createPolicy()
        policy.sessionThresholdPercent = nil
        let world = HeaderSightingWorld(
            policy: policy,
            wearing: Self.work.hat,
            liveCredential: Self.work,
            readings: [:],
            interval: 300
        )

        XCTAssertEqual(
            getDecision(for: createReading(session: 100, weekly: 10), in: world),
            .underTheThresholds,
            "with the session threshold switched off, a session at 100 percent crosses nothing"
        )
    }

    func testAHatThePollNeverReadIsNotYetKnownToBeOverTheLine() {
        let world = HeaderSightingWorld(
            policy: createPolicy(),
            wearing: Self.work.hat,
            liveCredential: Self.work,
            readings: [:],
            interval: 300
        )

        XCTAssertEqual(getDecision(for: createReading(session: 86), in: world), .pollNow)
    }

    func testTheSwitchBeingOffIsReportedBeforeAnythingElse() {
        let world = createWorld(
            isOn: false,
            live: nil
        )

        XCTAssertEqual(getDecision(for: createReading(session: 10), in: world), .autoSwitchIsOff)
    }
}
