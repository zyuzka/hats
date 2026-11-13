import Darwin
import XCTest
@testable import Hats

final class SessionWindowsChannelTests: XCTestCase {
    private var work: URL!
    private let hook = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("plugin/scripts/window-fill.py")

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("session-windows-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private func runTheHook(_ arguments: [String], environment: [String: String], input: String = "") throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-I", hook.path] + arguments
        var inherited = ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"]
        inherited.merge(environment) { _, new in new }
        process.environment = inherited
        let output = Pipe()
        let entry = Pipe()
        process.standardOutput = output
        process.standardInput = entry
        try process.run()
        entry.fileHandleForWriting.write(Data(input.utf8))
        try entry.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "the hook exits 0")

        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    func testTheHookWritesIntoTheFolderHatsReadsWithTheSameStateHome() throws {
        let home = try XCTUnwrap(
            ProcessInfo.processInfo.environment[StateDirectory.overrideName],
            "run the suite with HATS_STATE_HOME set, as CLAUDE.md and CI do"
        )

        let printed = try runTheHook(["where"], environment: [StateDirectory.overrideName: home])

        XCTAssertEqual(printed, SessionWindows.defaultFolder.path)
    }

    func testTheHookWritesIntoTheFolderHatsReadsWithoutAStateHome() throws {
        let printed = try runTheHook(["where"], environment: ["HOME": NSHomeDirectory()])

        XCTAssertEqual(
            printed,
            StateDirectory.defaultLocation.appendingPathComponent(SessionWindow.folderName).path,
            "with no HATS_STATE_HOME both take ~/Library/Application Support/Hats; the hook from HOME, Hats from "
                + "NSHomeDirectory(), which is why the hook runs here with HOME set to it"
        )
    }

    func testARecordTheHookWritesIsOneHatsReads() throws {
        let transcript = work.appendingPathComponent("t.jsonl")
        let answer = """
            {"type":"assistant","timestamp":"2026-11-13T10:00:00.000Z","message":{"model":"claude-opus-5-5",\
            "id":"msg_1","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":2,\
            "cache_creation_input_tokens":1035,"cache_read_input_tokens":448622,"output_tokens":9}}}

            """
        try Data(answer.utf8).write(to: transcript)
        let input = """
            {"session_id":"5a32129e-d019","transcript_path":"\(transcript.path)","cwd":"/tmp/hats",\
            "hook_event_name":"UserPromptSubmit","session_title":"Fix the login"}
            """

        _ = try runTheHook(
            [],
            environment: [StateDirectory.overrideName: work.path, "CLAUDE_CODE_SESSION_ATTENDED": "1"],
            input: input
        )
        let read = SessionWindowFile.getRecord(
            "5a32129e-d019.json",
            in: work.appendingPathComponent(SessionWindow.folderName)
        )

        guard case .read(let window) = read else { return XCTFail("Hats refused the hook's record: \(read)") }
        XCTAssertEqual(window.tokens, 449_659)
        XCTAssertEqual(window.window, 1_000_000)
        XCTAssertEqual(window.percent, 45)
        XCTAssertEqual(window.title, "Fix the login")
        XCTAssertEqual(SessionWindow.getMenuRows([window], now: window.measuredAt).first?.value, "45%")
    }

    func testTheFolderIsMadeForHatsAloneAndAnExistingOneIsKept() throws {
        let folder = work.appendingPathComponent("state/\(SessionWindow.folderName)")

        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder), "a folder already there is no trouble")

        var facts = stat()
        XCTAssertEqual(lstat(folder.path, &facts), 0)
        XCTAssertEqual(facts.st_mode & 0o777, 0o700, "Hats makes the folder for its user only")
    }

    private func place(_ session: String, in folder: URL) throws {
        let fields: [String: Any] = [
            "session": session,
            "tokens": 312_000,
            "window": NSNull(),
            "percent": NSNull(),
            "state": "read",
            "measured_at": ISO8601DateFormatter().string(from: Date()),
        ]
        let staged = folder.appendingPathComponent(".tmp-\(session)")
        try JSONSerialization.data(withJSONObject: fields).write(to: staged)
        XCTAssertEqual(rename(staged.path, folder.appendingPathComponent("\(session).json").path), 0)
    }

    func testTheWatchReadsAtStartAndSeesARecordAppearLater() throws {
        let folder = work.appendingPathComponent(SessionWindow.folderName)
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place("at-start", in: folder)
        let summed = expectation(description: "the start-up summary goes to the journal the watch was given")
        let watch = SessionWindows(folder: folder, log: { event, details in
            if event == "sessionWindows.read", details["readable"] == "1" { summed.fulfill() }
        })
        let startUp = expectation(description: "the record already there is read at start")
        let later = expectation(description: "a record written later is seen through the folder's events")
        watch.onChange = { [unowned watch] in
            switch watch.windows.map(\.session) {
            case ["at-start"]: startUp.fulfill()
            case ["at-start", "later"]: later.fulfill()
            default: break
            }
        }

        watch.start()
        defer { watch.stop() }
        wait(for: [startUp, summed], timeout: 5)
        try place("later", in: folder)

        wait(for: [later], timeout: 5)
    }

    func testAFolderRemovedAndMadeAgainIsWatchedAgain() throws {
        let folder = work.appendingPathComponent(SessionWindow.folderName)
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place("before", in: folder)
        let watch = SessionWindows(folder: folder, log: { _, _ in })
        let first = expectation(description: "the first read shows the first session")
        let again = expectation(description: "the session placed in the new folder is shown")
        let watched = expectation(description: "a session placed later is seen through the new folder's events")
        watch.onChange = { [unowned watch] in
            switch watch.windows.map(\.session) {
            case ["before"]: first.fulfill()
            case ["after"]: again.fulfill()
            case ["after", "later"]: watched.fulfill()
            default: break
            }
        }
        watch.start()
        defer { watch.stop() }
        wait(for: [first], timeout: 5)

        try FileManager.default.removeItem(at: folder)
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place("after", in: folder)
        wait(for: [again], timeout: 10)
        try place("later", in: folder)

        wait(for: [watched], timeout: 10)
    }

    func testAFolderThatCannotBeMadeEmptiesTheListAndIsTriedAgain() throws {
        let folder = work.appendingPathComponent(SessionWindow.folderName)
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place("earlier", in: folder)
        let lines = NSLock()
        var told: [String] = []
        let secondLine = expectation(description: "the same reason is told a second time")
        secondLine.isInverted = true
        let watch = SessionWindows(folder: folder, retryAfter: 0.5, log: { event, details in
            guard event == "sessionWindows.unwatched" else { return }
            lines.lock()
            told.append(details["reason"] ?? "")
            let count = told.count
            lines.unlock()
            if count == 2 { secondLine.fulfill() }
        })
        let shown = expectation(description: "the first session is shown")
        let emptied = expectation(description: "a folder that cannot be made leaves no old rows behind")
        let back = expectation(description: "once the folder can be made, its session is shown")
        watch.onChange = { [unowned watch] in
            switch watch.windows.map(\.session) {
            case ["earlier"]: shown.fulfill()
            case []: emptied.fulfill()
            case ["later"]: back.fulfill()
            default: break
            }
        }
        watch.start()
        defer { watch.stop() }
        wait(for: [shown], timeout: 5)

        try FileManager.default.moveItem(at: folder, to: work.appendingPathComponent("moved-away"))
        try Data("x".utf8).write(to: folder)
        wait(for: [emptied], timeout: 10)
        wait(for: [secondLine], timeout: 1.6)
        try FileManager.default.removeItem(at: folder)
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place("later", in: folder)

        wait(for: [back], timeout: 10)
        lines.lock()
        XCTAssertEqual(told, ["it is a link or not a folder"], "one journal line for one reason, however many tries")
        lines.unlock()
    }

    func testAFolderThatIsALinkIsNotWatched() throws {
        let elsewhere = work.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let folder = work.appendingPathComponent(SessionWindow.folderName)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: elsewhere)
        let told = expectation(description: "the refusal is in the journal")
        let watch = SessionWindows(folder: folder, log: { event, details in
            if event == "sessionWindows.unwatched", details["reason"] == "it is a link or not a folder" { told.fulfill() }
        })

        watch.start()
        defer { watch.stop() }

        wait(for: [told], timeout: 5)
        XCTAssertEqual(watch.windows, [])
    }
}
