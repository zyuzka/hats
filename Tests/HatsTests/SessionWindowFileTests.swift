import Darwin
import XCTest
@testable import Hats

final class SessionWindowFileTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-window-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func fields(_ changes: [String: Any] = [:]) -> [String: Any] {
        var base: [String: Any] = [
            "session": "5a32129e-d019",
            "cwd": "/Volumes/work/projects/hats",
            "title": NSNull(),
            "tokens": 449_659,
            "window": 1_000_000,
            "percent": 45,
            "state": "read",
            "model": "claude-opus-5-5",
            "message": "msg_1",
            "measured_at": "2026-11-13T10:00:00.000Z",
            "compactions": 0,
            "compaction": NSNull(),
            "compacted_at": NSNull(),
            "event": "PostToolUse",
            "written_at": "2026-11-13T10:00:01Z",
        ]
        for (key, value) in changes { base[key] = value }
        return base
    }

    private func write(_ fields: [String: Any], as name: String = "5a32129e-d019.json") throws {
        let data = try JSONSerialization.data(withJSONObject: fields)
        try data.write(to: folder.appendingPathComponent(name))
    }

    private func read(_ name: String = "5a32129e-d019.json") -> SessionWindowRead {
        SessionWindowFile.getRecord(name, in: folder)
    }

    private func isSkipped(_ read: SessionWindowRead) -> Bool {
        if case .skipped = read { return true }
        return false
    }

    func testARecordTheHookWritesIsReadWithItsNumbers() throws {
        try write(fields())

        let read = read()

        guard case .read(let window) = read else { return XCTFail("read as \(read)") }
        XCTAssertEqual(window.session, "5a32129e-d019")
        XCTAssertEqual(window.cwd, "/Volumes/work/projects/hats")
        XCTAssertNil(window.title)
        XCTAssertEqual(window.tokens, 449_659)
        XCTAssertEqual(window.window, 1_000_000)
        XCTAssertEqual(window.percent, 45)
        XCTAssertEqual(window.state, .read)
        XCTAssertEqual(window.measuredAt, UsageReading.date(from: "2026-11-13T10:00:00.000Z"))
    }

    func testACompactedRecordAndARecordWithoutAWindowAreRead() throws {
        try write(fields(["state": "compacted", "tokens": NSNull(), "window": NSNull(), "percent": NSNull()]))
        guard case .read(let compacted) = read() else { return XCTFail("a compacted record is a record") }
        XCTAssertEqual(compacted.state, .compacted)
        XCTAssertNil(compacted.tokens)

        try write(fields(["tokens": 312_000, "window": NSNull(), "percent": NSNull()]))
        guard case .read(let unknown) = read() else { return XCTFail("an unknown window is not a defect") }
        XCTAssertEqual(unknown.tokens, 312_000)
        XCTAssertNil(unknown.window)
        XCTAssertNil(unknown.percent)
    }

    func testEveryMalformedRecordIsSkippedWithItsReason() throws {
        let cases: [(String, [String: Any])] = [
            ("percent as a string", ["percent": "45"]),
            ("percent as true", ["percent": true]),
            ("tokens with a fraction", ["tokens": 1.5]),
            ("title as a number", ["title": 5]),
            ("percent above 100", ["tokens": 1_010_000, "percent": 101]),
            ("percent below 0", ["percent": -1]),
            ("percent not matching tokens and window", ["percent": 44]),
            ("percent without a window", ["window": NSNull()]),
            ("a window of zero", ["window": 0, "percent": 0]),
            ("tokens missing", ["tokens": NSNull()]),
            ("tokens negative", ["tokens": -5, "percent": 0]),
            ("a compacted record with numbers", ["state": "compacted"]),
            ("an unknown state", ["state": "guessed"]),
            ("measured_at not a time", ["measured_at": "yesterday"]),
            ("measured_at missing", ["measured_at": NSNull()]),
            ("session missing", ["session": NSNull()]),
        ]
        for (why, change) in cases {
            try write(fields(change))
            XCTAssertTrue(isSkipped(read()), why)
        }
    }

    func testFieldsHatsDoesNotUseMayChangeTheirTypes() throws {
        try write(fields([
            "model": 5,
            "message": ["id": "msg_1"],
            "compactions": "x",
            "compaction": true,
            "compacted_at": -1,
            "event": NSNull(),
            "written_at": 1.5,
        ]))

        let read = read()

        guard case .read(let window) = read else { return XCTFail("only the fields Hats reads decide: \(read)") }
        XCTAssertEqual(window.percent, 45)
    }

    func testAFileThatIsNotARecordIsSkipped() throws {
        try Data("not json".utf8).write(to: folder.appendingPathComponent("5a32129e-d019.json"))
        XCTAssertTrue(isSkipped(read()), "not JSON")
        try Data("[1, 2]".utf8).write(to: folder.appendingPathComponent("5a32129e-d019.json"))
        XCTAssertTrue(isSkipped(read()), "JSON but not an object")
    }

    func testTheNameMustBeTheSessionItCarries() throws {
        try write(fields(), as: "other.json")
        XCTAssertEqual(read("other.json"), .skipped("its name is not its session"))

        try write(fields(["session": "../x"]), as: "..-x.json")
        XCTAssertTrue(isSkipped(read("..-x.json")), "a session id outside [A-Za-z0-9-] is not a session")
    }

    func testALinkAPipeAndAFolderAreSkippedWithoutFollowingOrWaiting() throws {
        try write(fields(), as: "target.json")
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("5a32129e-d019.json"),
            withDestinationURL: folder.appendingPathComponent("target.json")
        )
        XCTAssertEqual(read(), .skipped("it is a link"))

        XCTAssertEqual(mkfifo(folder.appendingPathComponent("pipe.json").path, 0o600), 0)
        let started = Date()
        XCTAssertEqual(read("pipe.json"), .skipped("it is not a regular file"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "a named pipe with no writer must not hold the reader")

        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("folder.json"),
            withIntermediateDirectories: false
        )
        XCTAssertEqual(read("folder.json"), .skipped("it is not a regular file"))
        XCTAssertEqual(read("missing.json"), .skipped(String(cString: strerror(ENOENT))))
    }

    func testAFileUpTo64KBIsReadAndALargerOneIsNot() throws {
        let base = try JSONSerialization.data(withJSONObject: fields(["title": ""]))
        let room = SessionWindowFile.sizeCap - base.count
        try write(fields(["title": String(repeating: "t", count: room)]))
        let atTheCap = try FileManager.default.attributesOfItem(
            atPath: folder.appendingPathComponent("5a32129e-d019.json").path
        )[.size] as? Int
        XCTAssertEqual(atTheCap, SessionWindowFile.sizeCap)
        XCTAssertFalse(isSkipped(read()), "exactly 64 KB is within the cap")

        try write(fields(["title": String(repeating: "t", count: room + 1)]))
        XCTAssertEqual(read(), .skipped("it is larger than 64 KB"))
    }

    func testThePercentIsRoundedTheWayTheStatusLineRoundsIt() {
        XCTAssertEqual(SessionWindow.getPercent(tokens: 89_000, window: 200_000), 45, "44.5 rounds up, as Math.round")
        XCTAssertEqual(SessionWindow.getPercent(tokens: 445_000, window: 1_000_000), 45)
        XCTAssertEqual(SessionWindow.getPercent(tokens: 444_999, window: 1_000_000), 44)
        XCTAssertEqual(SessionWindow.getPercent(tokens: 449_659, window: 1_000_000), 45)
        XCTAssertEqual(SessionWindow.getPercent(tokens: 250_000, window: 200_000), 100, "held at 100")
        XCTAssertEqual(SessionWindow.getPercent(tokens: Int.max, window: 1), 100, "no overflow on a huge count")
        XCTAssertEqual(SessionWindow.getPercent(tokens: 0, window: 200_000), 0)
    }
}
