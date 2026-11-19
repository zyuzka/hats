import XCTest
@testable import Hats

final class CodexContinueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_795_101_000)

    private func mark(_ percent: Int, _ event: String? = "Stop", ago: TimeInterval = 25, session: String = "s1") -> CodexWindowMark {
        CodexWindowMark(session: session, percent: percent, event: event, writtenAt: now.addingTimeInterval(-ago))
    }

    func testATurnEndedPastTheSaveThresholdAndIdleFor20SecondsIsDue() {
        var memory = CodexContinueMemory()
        XCTAssertEqual(memory.due([mark(72)], warn: 60, save: 70, now: now), [mark(72)])
        XCTAssertEqual(memory.due([mark(70)], warn: 60, save: 70, now: now), [mark(70)], "at the threshold counts")
    }

    func testBelowTheSaveThresholdNothingIsDue() {
        var memory = CodexContinueMemory()
        XCTAssertEqual(memory.due([mark(65)], warn: 60, save: 70, now: now), [])
        XCTAssertEqual(memory.due([mark(69)], warn: 60, save: 70, now: now), [])
    }

    func testAnIdleShorterThan20SecondsIsNotDueYet() {
        var memory = CodexContinueMemory()
        XCTAssertEqual(memory.due([mark(72, ago: 19)], warn: 60, save: 70, now: now), [])
        XCTAssertEqual(memory.due([mark(72, ago: 20)], warn: 60, save: 70, now: now), [mark(72, ago: 20)])
    }

    func testOnlyAnEndOfTurnIsDueNotTheStartOfOne() {
        var memory = CodexContinueMemory()
        XCTAssertEqual(memory.due([mark(72, "UserPromptSubmit")], warn: 60, save: 70, now: now), [])
        XCTAssertEqual(memory.due([mark(72, nil)], warn: 60, save: 70, now: now), [], "a file from before the event field")
    }

    func testAnOldEndOfTurnIsNotDue() {
        var memory = CodexContinueMemory()
        XCTAssertEqual(memory.due([mark(72, ago: 10 * 60 + 1)], warn: 60, save: 70, now: now), [])
    }

    func testEitherThresholdOffMeansNothingIsDue() {
        var memory = CodexContinueMemory()
        XCTAssertEqual(memory.due([mark(72)], warn: 60, save: nil, now: now), [])
        XCTAssertEqual(memory.due([mark(72)], warn: nil, save: 70, now: now), [])
    }

    func testAfterActingTheSessionWaitsUntilItWasBelowTheWarningThreshold() {
        var memory = CodexContinueMemory()
        memory.noteActed(mark(72))
        XCTAssertEqual(memory.due([mark(75, ago: 30)], warn: 60, save: 70, now: now), [], "a later turn still past save")
        XCTAssertEqual(memory.due([mark(62, ago: 40)], warn: 60, save: 70, now: now), [], "between the thresholds")
        XCTAssertEqual(memory.due([mark(30, ago: 50)], warn: 60, save: 70, now: now), [])
        XCTAssertEqual(memory.due([mark(73, ago: 60)], warn: 60, save: 70, now: now), [mark(73, ago: 60)])
    }

    func testAHandledEndOfTurnIsNotTriedAgainButTheNextOneIs() {
        var memory = CodexContinueMemory()
        memory.noteHandled(mark(72))
        XCTAssertEqual(memory.due([mark(72)], warn: 60, save: 70, now: now), [])
        XCTAssertEqual(memory.due([mark(74, ago: 21)], warn: 60, save: 70, now: now), [mark(74, ago: 21)])
    }

    func testSessionsAreDueOldestFirstAndApart() {
        var memory = CodexContinueMemory()
        memory.noteActed(mark(72, session: "a"))
        let marks = [mark(80, ago: 30, session: "b"), mark(72, ago: 25, session: "a"), mark(71, ago: 40, session: "c")]
        XCTAssertEqual(memory.due(marks, warn: 60, save: 70, now: now).map(\.session), ["c", "b"])
    }

    func testTheMarksAreReadFromTheWindowFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hats-cc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = #"{"session": "01a1-x", "window": 475000, "tokens": 1, "percent": 72, "cwd": "/w", "event": "Stop", "#
            + #""written_at": "2026-11-19T15:12:00Z"}"#
        try Data(good.utf8).write(to: folder.appendingPathComponent("01a1-x.json"))
        try Data(#"{"session": "other", "percent": 72}"#.utf8).write(to: folder.appendingPathComponent("01a1-y.json"))
        try Data(#"{"session": "../x", "percent": 72}"#.utf8).write(to: folder.appendingPathComponent("..x.json"))
        try Data("not json".utf8).write(to: folder.appendingPathComponent("bad.json"))
        let scan = CodexContinue.scan(folder, now: Date())
        let stamp = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-19T15:12:00Z"))
        XCTAssertEqual(scan.marks, [CodexWindowMark(session: "01a1-x", percent: 72, event: "Stop", writtenAt: stamp)])
        XCTAssertEqual(scan.present, ["01a1-x", "01a1-y", "bad"])
        let old = Date().addingTimeInterval(-(CodexContinue.freshFor + 60))
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: folder.appendingPathComponent("01a1-x.json").path)
        XCTAssertEqual(CodexContinue.scan(folder, now: Date()).marks, [], "a file not touched for 10 minutes is not read")
    }

    func testAThreadGoneFromTheFolderForMoreThan10MinutesIsForgotten() {
        var memory = CodexContinueMemory()
        memory.noteActed(mark(72))
        _ = memory.due(CodexWindowScan(marks: [], present: ["s1"]), warn: 60, save: 70, now: now.addingTimeInterval(3600))
        XCTAssertEqual(memory.remembered, ["s1"], "its file is still there")
        _ = memory.due(CodexWindowScan(marks: [], present: []), warn: 60, save: 70, now: now.addingTimeInterval(9 * 60))
        XCTAssertEqual(memory.remembered, ["s1"], "gone, but not for 10 minutes yet")
        _ = memory.due(CodexWindowScan(marks: [], present: []), warn: 60, save: 70, now: now.addingTimeInterval(3600))
        XCTAssertEqual(memory.remembered, [])
    }
}
