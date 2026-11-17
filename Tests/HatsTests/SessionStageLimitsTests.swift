import XCTest
@testable import Hats

final class SessionStageLimitsTests: XCTestCase {
    static let resets = "2026-11-17T15:00:00Z"

    static func event(_ at: String, percent: Double, worn: String = "work", reason: String = "no_hat") -> [String: Any] {
        [
            "at": at,
            "percent": percent,
            "worn": worn,
            "reason": reason,
        ]
    }

    static func episode(
        resetsAt: String = resets,
        save: Any = 80,
        warned: Any = NSNull(),
        asked: Any = NSNull(),
        previous: Any = NSNull()
    ) -> [String: Any] {
        [
            "resets_at": resetsAt,
            "percent": 81.5,
            "warn_percent": 70,
            "save_percent": save,
            "warned": warned,
            "asked": asked,
            "previous": previous,
        ]
    }

    private func parse(_ changes: [String: Any]) throws -> SessionStageRead {
        let data = try JSONSerialization.data(withJSONObject: SessionStageFileTests.fields(changes))

        return SessionStageFile.getRecord(parsing: data, name: "5a32129e-d019.json")
    }

    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(UsageReading.date(from: text))
    }

    func testARecordWithoutAWindowStageButWithLimitsIsReadAndItsEventsWithIt() throws {
        let limits: [String: Any] = [
            "five_hour": Self.episode(
                warned: Self.event("2026-11-17T12:40:02.800Z", percent: 72),
                asked: Self.event("2026-11-17T12:52:10.115Z", percent: 81.5)
            ),
            "seven_day": NSNull(),
        ]

        let read = try parse(["stage": NSNull(), "limits": limits])

        guard case .read(let stage) = read else { return XCTFail("\(read)") }
        XCTAssertNil(stage.kind)
        XCTAssertEqual(stage.limitEpisodes, [
            LimitEpisode(
                limit: .fiveHour,
                resetsAt: try date(Self.resets),
                percent: 81.5,
                warnPercent: 70,
                savePercent: 80,
                events: [
                    LimitEvent(stage: .warned, at: try date("2026-11-17T12:40:02.800Z"), percent: 72, worn: "work", reason: .noHat),
                    LimitEvent(stage: .asked, at: try date("2026-11-17T12:52:10.115Z"), percent: 81.5, worn: "work", reason: .noHat),
                ]
            ),
        ])
    }

    func testANullStageWithoutLimitsIsStillUnknown() throws {
        XCTAssertEqual(try parse(["stage": NSNull()]), .skipped("its stage is unknown"))
        XCTAssertEqual(try parse(["stage": NSNull(), "limits": NSNull()]), .skipped("its stage is unknown"))
        XCTAssertEqual(try parse(["stage": "cleaning", "limits": ["five_hour": NSNull()]]), .skipped("its stage is unknown"))
    }

    func testThePreviousEpisodeComesFirstAndTheWeeklyAfterTheFiveHour() throws {
        let previous = Self.episode(resetsAt: "2026-11-17T10:00:00Z", asked: Self.event("2026-11-17T09:00:00.000Z", percent: 80))
        let limits: [String: Any] = [
            "seven_day": Self.episode(resetsAt: "2026-11-24T17:00:00.000Z", warned: Self.event("2026-11-17T12:00:00.000Z", percent: 70)),
            "five_hour": Self.episode(previous: previous),
        ]

        guard case .read(let stage) = try parse(["limits": limits]) else { return XCTFail("a good record") }

        XCTAssertEqual(stage.kind, .requested)
        XCTAssertEqual(stage.limitEpisodes.map(\.limit), [.fiveHour, .fiveHour, .sevenDay])
        XCTAssertEqual(stage.limitEpisodes.map(\.resetsAt), [
            try date("2026-11-17T10:00:00Z"),
            try date(Self.resets),
            try date("2026-11-24T17:00:00Z"),
        ])
        XCTAssertEqual(stage.limitEpisodes.first?.events.map(\.stage), [.asked])
    }

    func testAFractionalLimitPercentIsANumberWhileTheWindowRoundsStayWhole() throws {
        let limits: [String: Any] = ["five_hour": Self.episode(warned: Self.event("2026-11-17T12:40:02.800Z", percent: 72.5))]

        guard case .read(let stage) = try parse(["limits": limits]) else { return XCTFail("a good record") }

        XCTAssertEqual(stage.limitEpisodes.first?.percent, 81.5)
        XCTAssertEqual(stage.limitEpisodes.first?.events.first?.percent, 72.5)
        XCTAssertEqual(try parse(["limits": limits, "warn_round": 1.5]), .skipped("it is not a session stage record"))
    }

    func testEveryReasonTheModNamesIsRead() throws {
        let reasons: [(String, LimitReason)] = [
            ("no_hat", .noHat),
            ("auto_switch_off", .autoSwitchOff),
            ("switch_threshold_off", .switchThresholdOff),
            ("hats_not_running", .hatsNotRunning),
        ]
        for (text, reason) in reasons {
            let limits: [String: Any] = ["five_hour": Self.episode(warned: Self.event("2026-11-17T12:40:02.800Z", percent: 72, reason: text))]

            guard case .read(let stage) = try parse(["limits": limits]) else {
                XCTFail("\(text) skipped the record")
                continue
            }
            XCTAssertEqual(stage.limitEpisodes.first?.events.first?.reason, reason, text)
        }
    }

    func testABrokenLimitKeepsTheWindowStageWithoutEpisodesAndNamesTheTrouble() throws {
        let good = Self.event("2026-11-17T12:40:02.800Z", percent: 72)
        let broken: [(String, [String: Any])] = [
            ("unknown reason", ["five_hour": Self.episode(warned: Self.event("2026-11-17T12:40:02.800Z", percent: 72, reason: "tired"))]),
            ("empty worn", ["five_hour": Self.episode(warned: Self.event("2026-11-17T12:40:02.800Z", percent: 72, worn: ""))]),
            ("event percent above 100", ["five_hour": Self.episode(warned: Self.event("2026-11-17T12:40:02.800Z", percent: 101))]),
            ("event at not a time", ["five_hour": Self.episode(warned: Self.event("soon", percent: 72))]),
            ("resets_at not a time", ["five_hour": Self.episode(resetsAt: "later", warned: good)]),
            ("save below warn", ["five_hour": Self.episode(save: 60, warned: good)]),
            ("broken previous", ["five_hour": Self.episode(previous: Self.episode(resetsAt: "later"))]),
        ]
        for (name, limits) in broken {
            guard case .read(let stage) = try parse(["limits": limits]) else {
                XCTFail("\(name): the window stage was dropped")
                continue
            }
            XCTAssertEqual(stage.kind, .requested, name)
            XCTAssertEqual(stage.limitEpisodes, [], name)
            XCTAssertEqual(stage.limitTrouble, "its five_hour limit is not readable", name)
        }
        guard case .read(let shape) = try parse(["limits": ["five_hour": ["percent": "81"]]]) else { return XCTFail("dropped") }
        XCTAssertEqual(shape.limitTrouble, "its limits are not readable")
        guard case .read(let text) = try parse(["limits": "none"]) else { return XCTFail("dropped") }
        XCTAssertEqual(text.limitTrouble, "its limits are not readable")
        XCTAssertEqual(try parse(["stage": NSNull(), "limits": ["five_hour": Self.episode(resetsAt: "later")]]),
                       .skipped("its five_hour limit is not readable"),
                       "with no window stage there is nothing left to keep")
    }

    func testAnUnknownStageKeepsTheLimitEpisodesAndAnEmptyListIsNoEpisodes() throws {
        let limits: [String: Any] = ["five_hour": Self.episode(warned: Self.event("2026-11-17T12:40:02.800Z", percent: 72))]

        guard case .read(let stage) = try parse(["stage": "cleaning", "limits": limits]) else {
            return XCTFail("an unknown stage dropped the limit episodes")
        }

        XCTAssertNil(stage.kind)
        XCTAssertEqual(stage.limitEpisodes.count, 1)
        XCTAssertFalse(SessionStageLimits.Found.episodes([]).hasEpisodes)
        XCTAssertTrue(SessionStageLimits.Found.episodes(stage.limitEpisodes).hasEpisodes)
        XCTAssertEqual(try parse(["stage": NSNull(), "limits": ["five_hour": NSNull(), "seven_day": NSNull()]]),
                       .skipped("its stage is unknown"))
    }

    func testTheTroubleOfBrokenLimitsIsJournaledOncePerFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stage-limits-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var lines: [(String, [String: String])] = []
        var scan = SessionThresholdsScan(log: { event, details in lines.append((event, details)) })
        let file = folder.appendingPathComponent("5a32129e-d019.json")
        let now = try XCTUnwrap(UsageReading.date(from: "2027-01-15T08:00:00Z"))
        let broken: [String: Any] = ["limits": ["five_hour": Self.episode(resetsAt: "later")]]
        var changed = broken
        changed["percent"] = 57

        try JSONSerialization.data(withJSONObject: SessionStageFileTests.fields(broken)).write(to: file)
        let first = try XCTUnwrap(scan.findStages(in: folder, now: now))
        try JSONSerialization.data(withJSONObject: SessionStageFileTests.fields(changed)).write(to: file)
        let second = try XCTUnwrap(scan.findStages(in: folder, now: now))

        XCTAssertEqual(first.stages.map(\.kind), [.requested], "the window stage stays")
        XCTAssertEqual(second.stages.map(\.percent), [57])
        XCTAssertEqual(lines.map(\.0), ["sessionThresholds.limitsSkipped"])
        XCTAssertEqual(lines.first?.1["reason"], "its five_hour limit is not readable")
    }

    func testAWindowStageRecordWithoutLimitsHasNoEpisodes() throws {
        guard case .read(let stage) = try parse([:]) else { return XCTFail("a good record") }

        XCTAssertEqual(stage.limitEpisodes, [])
        XCTAssertEqual(stage.kind, .requested)
    }
}
