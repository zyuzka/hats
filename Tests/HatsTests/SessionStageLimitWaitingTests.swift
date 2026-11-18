import XCTest
@testable import Hats

final class SessionStageLimitWaitingTests: XCTestCase {
    static func loadTheSharedSample() throws -> Data {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugin/tests/fixtures/stage-limit-waiting.json")

        return try Data(contentsOf: fixture)
    }

    static func stamp(_ text: String) -> Date {
        UsageReading.date(from: text) ?? .distantPast
    }

    private func readTheSample(changing change: (inout [String: Any]) -> Void = { _ in }) throws -> SessionStage {
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.loadTheSharedSample()) as? [String: Any])
        change(&fields)
        let session = try XCTUnwrap(fields["session"] as? String)
        let data = try JSONSerialization.data(withJSONObject: fields)
        let read = SessionStageFile.getRecord(parsing: data, name: session + ".json")
        guard case .read(let stage) = read else {
            XCTFail("the shared sample was not read: \(read)")
            throw CocoaError(.fileReadCorruptFile)
        }

        return stage
    }

    private func changeWaiting(_ limit: String, _ key: String, to value: Any, in fields: inout [String: Any]) {
        var limits = fields["limits"] as? [String: Any] ?? [:]
        var episode = limits[limit] as? [String: Any] ?? [:]
        var waiting = episode["waiting"] as? [String: Any] ?? [:]
        waiting[key] = value
        episode["waiting"] = waiting
        limits[limit] = episode
        fields["limits"] = limits
    }

    func testTheSharedSampleIsReadWithItsWaitingEventsAsTheAnchorStage() throws {
        let stage = try readTheSample()

        XCTAssertNil(stage.limitTrouble)
        let fiveHour = try XCTUnwrap(stage.limitEpisodes.first { $0.limit == .fiveHour })
        XCTAssertEqual(fiveHour.events.map(\.stage), [.warned, .asked], "the waiting event shares the anchor stage")
        let waiting = try XCTUnwrap(fiveHour.events.last)
        XCTAssertEqual(waiting.at, Self.stamp("2026-11-14T14:11:00.250Z"))
        XCTAssertEqual(waiting.worn, "work")
        XCTAssertEqual(waiting.reason, .noHat)
        XCTAssertEqual(waiting.percent, 81)
        XCTAssertEqual(waiting.wait, LimitWait(
            until: Self.stamp("2026-11-14T14:15:00.000Z"),
            origin: .hat,
            drainMinutes: 10,
            cancelledAt: nil
        ))
        XCTAssertNil(fiveHour.events.first?.wait, "a warning is not a wait")

        let sevenDay = try XCTUnwrap(stage.limitEpisodes.first { $0.limit == .sevenDay })
        XCTAssertEqual(sevenDay.events.count, 1)
        XCTAssertEqual(sevenDay.events.first?.wait, LimitWait(
            until: Self.stamp("2026-11-14T14:21:00.250Z"),
            origin: .deferred,
            drainMinutes: 10,
            cancelledAt: Self.stamp("2026-11-14T14:15:00.000Z")
        ), "a cancelled wait is still read: it stays evidence for the notices")
    }

    func testAWaitingEventWithABrokenFieldMakesTheLimitsUnreadable() throws {
        let broken: [(String, Any)] = [
            ("origin", "later"),
            ("until", "soon"),
            ("drain_minutes", 0),
            ("cancelled_at", "never"),
            ("cancelled_at", 5),
        ]
        for (key, value) in broken {
            let stage = try readTheSample {
                $0["stage"] = "warned"
                changeWaiting("five_hour", key, to: value, in: &$0)
            }
            XCTAssertEqual(stage.limitTrouble, "its five_hour limit is not readable", key)
            XCTAssertEqual(stage.limitEpisodes, [], key)
        }
        let origins = try LimitWaitOrigin.allCases.map { origin in
            try readTheSample { changeWaiting("five_hour", "origin", to: origin.rawValue, in: &$0) }
                .limitEpisodes.first?.events.last?.wait?.origin
        }
        XCTAssertEqual(origins, [.hat, .warned, .deferred])
    }
}
