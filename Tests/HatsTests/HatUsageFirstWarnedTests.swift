import XCTest
@testable import Hats

final class HatUsageFirstWarnedTests: XCTestCase {
    private var folder: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let fiveHourResets = SessionStageLimitWaitingTests.stamp("2026-11-14T15:00:00Z")
    private let weeklyResets = SessionStageLimitWaitingTests.stamp("2026-11-18T09:00:00Z")

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("first-warned-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func snapshot(wearing: String?, fiveHour: Date?, weekly: Date?) -> HatsSnapshot {
        let reading = UsageReading(
            session: UsageWindow(used: 81, limit: 100, resetsAt: fiveHour),
            weekly: UsageWindow(used: 82, limit: 100, resetsAt: weekly)
        )
        var snapshot = HatsSnapshot()
        snapshot.rows = ["work", "personal"].map { id in
            var hat = Account(id: id, email: "\(id)@company.com", browser: nil)
            hat.hasStoredCredentials = true
            return HatRowState(hat: hat, isWearing: id == wearing, usage: reading, usageTrouble: nil)
        }

        return snapshot
    }

    private func warned(_ at: String, worn: String = "work", early: Bool = false) -> LimitEvent {
        LimitEvent(
            stage: .warned,
            at: SessionStageLimitWaitingTests.stamp(at),
            percent: 72,
            worn: worn,
            reason: .noHat,
            early: early
        )
    }

    private func stage(_ session: String, _ episodes: [LimitEpisode]) -> SessionStage {
        SessionStage(
            session: session,
            cwd: nil,
            kind: nil,
            warnRound: 0,
            saveRound: 0,
            percent: nil,
            warnPercent: nil,
            savePercent: nil,
            at: now,
            drainMinutes: nil,
            limitEpisodes: episodes,
            limitTrouble: nil
        )
    }

    private func episode(_ limit: StageLimit, resetsAt: Date, _ events: [LimitEvent]) -> LimitEpisode {
        LimitEpisode(limit: limit, resetsAt: resetsAt, percent: 81, warnPercent: 70, savePercent: 80, events: events)
    }

    private func fields(wearing: String? = "work", fiveHour: Date?, weekly: Date?, stages: [SessionStage]) throws -> Any? {
        let record = HatUsageRecord.create(
            from: snapshot(wearing: wearing, fiveHour: fiveHour, weekly: weekly),
            readAt: [:],
            liveSlot: nil,
            aliveAt: nil,
            stages: stages
        )
        var file = HatUsageFile(url: folder.appendingPathComponent(HatUsageFile.name))
        XCTAssertEqual(file.setRecord(record, at: now), .written)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any]

        return written?["first_warned"]
    }

    func testTheSharedSampleGivesTheFirstWarningOfTheWornHatWithMilliseconds() throws {
        let data = try SessionStageLimitWaitingTests.loadTheSharedSample()
        let session = try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [String: Any])?["session"] as? String)
        guard case .read(let stage) = SessionStageFile.getRecord(parsing: data, name: session + ".json") else {
            return XCTFail("the shared sample was not read")
        }

        let found = try XCTUnwrap(fields(fiveHour: fiveHourResets, weekly: weeklyResets, stages: [stage]) as? [String: Any])

        XCTAssertEqual(found["five_hour"] as? [String: String], [
            "episode": "2026-11-14T15:00:00Z",
            "at": "2026-11-14T14:10:00.000Z",
        ])
        XCTAssertTrue(found["seven_day"] is NSNull, "a waiting event is not a warning")
    }

    func testTheEarliestWarningOfTheWornHatInTheHatsEpisodeIsTaken() {
        let stages = [
            stage("a", [episode(.fiveHour, resetsAt: fiveHourResets.addingTimeInterval(3599), [warned("2026-11-14T14:10:00Z")])]),
            stage("b", [episode(.fiveHour, resetsAt: fiveHourResets, [warned("2026-11-14T14:05:30.125Z", early: true)])]),
            stage("c", [episode(.fiveHour, resetsAt: fiveHourResets, [warned("2026-11-14T13:00:00Z", worn: "personal")])]),
            stage("d", [episode(.fiveHour, resetsAt: fiveHourResets.addingTimeInterval(-3600), [warned("2026-11-14T12:00:00Z")])]),
            stage("e", [episode(.sevenDay, resetsAt: fiveHourResets, [warned("2026-11-14T11:00:00Z")])]),
        ]

        let found = FirstWarned.find(in: stages, worn: "work", fiveHour: fiveHourResets, sevenDay: weeklyResets)

        XCTAssertEqual(found.fiveHour, FirstWarning(
            episode: fiveHourResets,
            at: SessionStageLimitWaitingTests.stamp("2026-11-14T14:05:30.125Z")
        ), "an early signal counts; another hat, an episode an hour away and the other limit do not")
        XCTAssertNil(found.sevenDay, "the weekly warning lies in another episode of the weekly limit")
        XCTAssertEqual(
            FirstWarned.find(in: stages, worn: "work", fiveHour: fiveHourResets, sevenDay: fiveHourResets).sevenDay?.at,
            SessionStageLimitWaitingTests.stamp("2026-11-14T11:00:00Z")
        )
    }

    func testThePreviousEpisodeOfAFileCountsWhenItIsTheHatsEpisode() {
        let stages = [
            stage("a", [
                episode(.fiveHour, resetsAt: fiveHourResets, [warned("2026-11-14T14:20:00Z")]),
                episode(.fiveHour, resetsAt: fiveHourResets.addingTimeInterval(18000), [warned("2026-11-14T18:00:00Z")]),
            ]),
        ]

        let found = FirstWarned.find(in: stages, worn: "work", fiveHour: fiveHourResets, sevenDay: nil)

        XCTAssertEqual(found.fiveHour?.at, SessionStageLimitWaitingTests.stamp("2026-11-14T14:20:00Z"))
    }

    func testWithoutAHatAReadingOrAWarningTheLimitIsNull() throws {
        let stages = [stage("a", [episode(.fiveHour, resetsAt: fiveHourResets, [warned("2026-11-14T14:10:00Z")])])]
        let empty: [String: NSNull] = [
            "five_hour": NSNull(),
            "seven_day": NSNull(),
        ]

        XCTAssertEqual(try fields(wearing: nil, fiveHour: fiveHourResets, weekly: weeklyResets, stages: stages) as? [String: NSNull],
                       empty, "no worn hat")
        XCTAssertEqual(try fields(fiveHour: nil, weekly: nil, stages: stages) as? [String: NSNull], empty, "no resets time")
        XCTAssertEqual(try fields(fiveHour: fiveHourResets, weekly: weeklyResets, stages: []) as? [String: NSNull], empty,
                       "no warning")
        XCTAssertEqual(
            FirstWarned.find(in: stages, worn: "personal", fiveHour: fiveHourResets, sevenDay: weeklyResets),
            FirstWarned(fiveHour: nil, sevenDay: nil),
            "a warning on another hat"
        )
    }
}
