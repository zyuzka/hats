import XCTest
@testable import Hats

final class CodexCompactLimitSyncTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("hats-codex-compact-sync-\(UUID().uuidString.prefix(8))")
    private var lines: [(String, [String: String])] = []
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private var root: URL { folder.appendingPathComponent("state") }
    private var config: URL { folder.appendingPathComponent("codex/config.toml") }
    private var windows: URL { root.appendingPathComponent(CodexCompactLimitSync.folderName) }

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeSync() -> CodexCompactLimitSync {
        CodexCompactLimitSync(
            root: root,
            config: config,
            log: { [weak self] name, details in self?.lines.append((name, details)) },
            now: { [unowned self] in clock }
        )
    }

    private func read() -> String? { try? String(contentsOf: config, encoding: .utf8) }

    private func writeWindow(_ window: Int, age: TimeInterval = 0) throws {
        let url = windows.appendingPathComponent("s-1.json")
        try "{\"window\": \(window)}".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: clock.addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    private func later() { clock = clock.addingTimeInterval(CodexCompactLimitSync.lookEvery) }

    private var names: [String] { lines.map(\.0) }

    func testTheLineIsWrittenOnceTheWindowIsKnown() throws {
        try "model = \"gpt\"\n".write(to: config, atomically: true, encoding: .utf8)
        let sync = makeSync()

        sync.sync(savePercent: 70)
        XCTAssertEqual(read(), "model = \"gpt\"\n")
        XCTAssertEqual(names, ["codexCompact.notWritten"])
        XCTAssertEqual(lines.first?.1["reason"], "windowUnknown")

        try writeWindow(475_000)
        later()
        sync.sync(savePercent: 70)
        XCTAssertEqual(read(), "model = \"gpt\"\nmodel_auto_compact_token_limit = 332500 # set by Hats\n")
        XCTAssertEqual(names.last, "codexCompact.written")
        XCTAssertEqual(lines.last?.1["tokens"], "332500")
        XCTAssertEqual(lines.last?.1["window"], "475000")
    }

    func testTheSaveThresholdOffRemovesTheLine() throws {
        try writeWindow(475_000)
        let sync = makeSync()
        sync.sync(savePercent: 70)
        XCTAssertEqual(read(), "model_auto_compact_token_limit = 332500 # set by Hats\n")

        sync.sync(savePercent: nil)
        XCTAssertEqual(read(), "")
        XCTAssertEqual(names.last, "codexCompact.removed")
        XCTAssertEqual(lines.last?.1["reason"], "saveOff")
    }

    func testAnotherSaveThresholdRewritesTheLineAtOnce() throws {
        try writeWindow(475_000)
        let sync = makeSync()
        sync.sync(savePercent: 70)
        sync.sync(savePercent: 80)
        XCTAssertEqual(read(), "model_auto_compact_token_limit = 380000 # set by Hats\n")
    }

    func testAForeignValueStaysAndIsJournaledOnce() throws {
        let text = "model_auto_compact_token_limit = 100000\n"
        try text.write(to: config, atomically: true, encoding: .utf8)
        try writeWindow(475_000)
        let sync = makeSync()

        sync.sync(savePercent: 70)
        later()
        sync.sync(savePercent: 70)
        XCTAssertEqual(read(), text)
        XCTAssertEqual(names, ["codexCompact.foreign"])
        XCTAssertEqual(lines.first?.1["value"], "100000")
    }

    func testASmallWindowWritesNoLineAndRemovesOurOld() throws {
        try writeWindow(475_000)
        let sync = makeSync()
        sync.sync(savePercent: 70)

        try writeWindow(50_000)
        later()
        sync.sync(savePercent: 70)
        XCTAssertEqual(read(), "")
        XCTAssertEqual(names.last, "codexCompact.removed")
        XCTAssertEqual(lines.last?.1["reason"], "smallWindow")
        XCTAssertEqual(lines.last?.1["tokens"], "35000")
    }

    func testASmallWindowWithoutAnOldLineIsJournaledAsNotWritten() throws {
        try writeWindow(50_000)
        makeSync().sync(savePercent: 70)
        XCTAssertNil(read())
        XCTAssertEqual(names, ["codexCompact.notWritten"])
        XCTAssertEqual(lines.first?.1["reason"], "smallWindow")
    }

    func testTheWindowsFolderIsLookedAtOnceInTenSecondsForTheSameThreshold() throws {
        let sync = makeSync()
        sync.sync(savePercent: 70)
        try writeWindow(475_000)
        sync.sync(savePercent: 70)
        XCTAssertNil(read(), "the folder is not read again within ten seconds")

        later()
        sync.sync(savePercent: 70)
        XCTAssertEqual(read(), "model_auto_compact_token_limit = 332500 # set by Hats\n")
    }

    func testNoConfigAndNoThresholdCreatesNothing() {
        makeSync().sync(savePercent: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
    }

    func testALineRemovedByHandIsWrittenBackOnTheNextLook() throws {
        try writeWindow(475_000)
        let sync = makeSync()
        sync.sync(savePercent: 70)
        later()
        sync.sync(savePercent: 70)
        XCTAssertEqual(names, ["codexCompact.written"], "an unchanged file writes no line")

        try "model = \"gpt\"\n".write(to: config, atomically: true, encoding: .utf8)
        later()
        sync.sync(savePercent: 70)
        XCTAssertEqual(read(), "model = \"gpt\"\nmodel_auto_compact_token_limit = 332500 # set by Hats\n")
        XCTAssertEqual(names, ["codexCompact.written", "codexCompact.written"])
    }

    func testAWindowGoneStaleRemovesOurLine() throws {
        try writeWindow(475_000)
        let sync = makeSync()
        sync.sync(savePercent: 70)
        XCTAssertEqual(read(), "model_auto_compact_token_limit = 332500 # set by Hats\n")

        try writeWindow(475_000, age: CodexCompactLimit.windowAge + 60)
        later()
        sync.sync(savePercent: 70)
        XCTAssertEqual(read(), "")
        XCTAssertEqual(names.last, "codexCompact.removed")
        XCTAssertEqual(lines.last?.1["reason"], "windowUnknown")
    }

    func testAForeignLineStaysWhenTheSaveThresholdIsOff() throws {
        let text = "model_auto_compact_token_limit = 100000\n"
        try text.write(to: config, atomically: true, encoding: .utf8)
        makeSync().sync(savePercent: nil)
        XCTAssertEqual(read(), text)
        XCTAssertEqual(names, ["codexCompact.foreign"])
        XCTAssertEqual(lines.first?.1["reason"], "saveOff")
    }
}
