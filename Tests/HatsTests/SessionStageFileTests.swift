import Darwin
import XCTest
@testable import Hats

final class SessionStageFileTests: XCTestCase {
    private var folder: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("session-stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    static func fields(_ changes: [String: Any] = [:]) -> [String: Any] {
        var base: [String: Any] = [
            "session": "5a32129e-d019",
            "cwd": "/Volumes/work/projects/hats",
            "stage": "requested",
            "warn_round": 1,
            "save_round": 1,
            "percent": 56,
            "warn_percent": 45,
            "save_percent": 55,
            "after_save": "offer_clear",
            "reason": NSNull(),
            "marker": NSNull(),
            "at": "2027-01-15T08:00:00Z",
        ]
        for (key, value) in changes { base[key] = value }

        return base
    }

    private func write(_ fields: [String: Any], as name: String = "5a32129e-d019.json") throws {
        try JSONSerialization.data(withJSONObject: fields).write(to: folder.appendingPathComponent(name))
    }

    private func read(_ name: String = "5a32129e-d019.json") -> SessionStageRead {
        SessionStageFile.getRecord(name, in: folder)
    }

    func testARecordTheModWritesIsReadWithItsRoundsAndNumbers() throws {
        try write(Self.fields())

        let read = read()

        XCTAssertEqual(read, .read(SessionStage(
            session: "5a32129e-d019",
            cwd: "/Volumes/work/projects/hats",
            kind: .requested,
            warnRound: 1,
            saveRound: 1,
            percent: 56,
            warnPercent: 45,
            savePercent: 55,
            at: now
        )))
    }

    func testEveryStageTheModNamesIsRead() throws {
        for stage in ["warned", "requested", "saved", "failed", "interrupted", "kept", "cleared"] {
            try write(Self.fields(["stage": stage]))

            guard case .read(let record) = read() else {
                XCTFail("\(stage) was skipped")
                continue
            }
            XCTAssertEqual(record.kind.rawValue, stage)
        }
    }

    func testARecordWithNullsTheModLegitimatelyWritesIsRead() throws {
        try write(Self.fields([
            "stage": "interrupted",
            "percent": NSNull(),
            "warn_percent": NSNull(),
            "save_percent": NSNull(),
            "reason": "plugin reloaded",
            "marker": "/tmp/x.json",
        ]))

        guard case .read(let record) = read() else { return XCTFail("a reload record is a good record") }
        XCTAssertNil(record.percent)
        XCTAssertNil(record.warnPercent)
        XCTAssertNil(record.savePercent)
    }

    func testAnUnknownStageOrAFieldOfTheWrongKindSkipsTheFile() throws {
        let broken: [(String, [String: Any])] = [
            ("unknown stage", ["stage": "cleaning"]),
            ("stage null after a refusal", ["stage": NSNull()]),
            ("round as text", ["warn_round": "1"]),
            ("round missing", ["save_round": NSNull()]),
            ("negative round", ["save_round": -1]),
            ("fractional round", ["warn_round": 1.5]),
            ("percent as text", ["percent": "56"]),
            ("percent above 100", ["percent": 101]),
            ("warn outside its range", ["warn_percent": 5]),
            ("save outside its range", ["save_percent": 99]),
            ("at not a time", ["at": "yesterday"]),
            ("reason of the wrong kind", ["reason": 3]),
            ("cwd of the wrong kind", ["cwd": ["/tmp"]]),
            ("another session's name", ["session": "other"]),
            ("a session id with a slash", ["session": "../5a32129e-d019"]),
        ]
        for (name, change) in broken {
            try write(Self.fields(change))

            guard case .skipped = read() else {
                XCTFail("\(name) was read")
                continue
            }
        }
        var withoutStage = Self.fields()
        withoutStage.removeValue(forKey: "stage")
        try write(withoutStage)
        XCTAssertEqual(read(), .skipped("its stage is unknown"))
    }

    func testAThresholdOutsideItsRangeIsNamedWithTheRangeHatsUses() throws {
        let warn = ContextThresholds.warnRange
        let save = ContextThresholds.saveRange

        try write(Self.fields(["warn_percent": warn.upperBound + 1]))
        XCTAssertEqual(read(), .skipped("warn_percent is outside \(warn.lowerBound)…\(warn.upperBound)"))
        try write(Self.fields(["save_percent": save.lowerBound - 1]))
        XCTAssertEqual(read(), .skipped("save_percent is outside \(save.lowerBound)…\(save.upperBound)"))
    }

    func testALinkAPartialWriteAndAnOversizedFileAreSkipped() throws {
        try write(Self.fields(), as: "real.json")
        XCTAssertEqual(symlink(folder.appendingPathComponent("real.json").path,
                               folder.appendingPathComponent("5a32129e-d019.json").path), 0)
        XCTAssertEqual(read(), .skipped("it is a link"))

        try FileManager.default.removeItem(at: folder.appendingPathComponent("5a32129e-d019.json"))
        try Data(#"{"session": "5a32129e-d019", "stage": "requ"#.utf8)
            .write(to: folder.appendingPathComponent("5a32129e-d019.json"))
        XCTAssertEqual(read(), .skipped("it is not a session stage record"), "the mod's write is not atomic")

        var big = Self.fields()
        big["marker"] = String(repeating: "x", count: 70 * 1024)
        try write(big)
        XCTAssertEqual(read(), .skipped("it is larger than \(SessionWindowFile.sizeCap / 1024) KB"))
    }
}
