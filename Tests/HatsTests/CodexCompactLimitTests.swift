import XCTest
@testable import Hats

final class CodexCompactLimitTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("hats-codex-compact-\(UUID().uuidString.prefix(8))")

    private var config: URL { folder.appendingPathComponent("codex/config.toml") }
    private var windows: URL { folder.appendingPathComponent("state/codex-windows") }

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func read() -> String? { try? String(contentsOf: config, encoding: .utf8) }

    private func writeWindow(_ session: String, _ window: Int, age: TimeInterval = 0) throws {
        let url = windows.appendingPathComponent("\(session).json")
        try "{\"session\": \"\(session)\", \"window\": \(window)}".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    private func setting(_ tokens: Int, in text: String?) -> CodexConfigEdit {
        CodexConfigText.setting(
            CodexCompactLimit.value(tokens),
            in: text,
            key: CodexCompactLimit.key,
            isOurs: CodexCompactLimit.isOurs
        )
    }

    private func removing(in text: String?) -> CodexConfigEdit {
        CodexConfigText.removing(in: text, key: CodexCompactLimit.key, isOurs: CodexCompactLimit.isOurs, mayEmpty: false)
    }

    func testTheLimitIsTheSaveThresholdOfTheModelWindow() {
        XCTAssertEqual(CodexCompactLimit.decide(savePercent: 70, window: 475_000), .write(tokens: 332_500, window: 475_000))
        XCTAssertEqual(CodexCompactLimit.decide(savePercent: 95, window: 272_000), .write(tokens: 258_400, window: 272_000))
    }

    func testNoLineWithoutASaveThresholdOrWithoutAWindow() {
        XCTAssertEqual(CodexCompactLimit.decide(savePercent: nil, window: 475_000), .saveOff)
        XCTAssertEqual(CodexCompactLimit.decide(savePercent: 70, window: nil), .windowUnknown)
    }

    func testALimitNotAbove40000IsASmallWindow() {
        XCTAssertEqual(CodexCompactLimit.decide(savePercent: 70, window: 50_000), .smallWindow(tokens: 35_000, window: 50_000))
        XCTAssertEqual(CodexCompactLimit.decide(savePercent: 50, window: 80_000), .smallWindow(tokens: 40_000, window: 80_000))
        XCTAssertEqual(CodexCompactLimit.decide(savePercent: 50, window: 80_002), .write(tokens: 40_001, window: 80_002))
    }

    func testOnlyANumberWithTheMarkIsOurs() {
        XCTAssertTrue(CodexCompactLimit.isOurs("332500 # set by Hats"))
        XCTAssertTrue(CodexCompactLimit.isOurs("332500    #   set by Hats"))
        XCTAssertFalse(CodexCompactLimit.isOurs("332500"))
        XCTAssertFalse(CodexCompactLimit.isOurs("332500 # mine"))
        XCTAssertFalse(CodexCompactLimit.isOurs("\"332500\" # set by Hats"))
        XCTAssertFalse(CodexCompactLimit.isOurs("-5 # set by Hats"))
        XCTAssertFalse(CodexCompactLimit.isOurs("# set by Hats"))
    }

    func testTheLineGoesAboveTheFirstTableAndReplacesOnlyOurOwn() {
        let text = "model = \"gpt\"\n\n[tui]\nfullscreen = true\n"
        XCTAssertEqual(setting(332_500, in: text), .changed(
            "model = \"gpt\"\n\nmodel_auto_compact_token_limit = 332500 # set by Hats\n[tui]\nfullscreen = true\n"
        ))
        let ours = "model_auto_compact_token_limit = 200000 # set by Hats\nmodel = \"gpt\"\n"
        XCTAssertEqual(setting(332_500, in: ours), .changed(
            "model_auto_compact_token_limit = 332500 # set by Hats\nmodel = \"gpt\"\n"
        ))
        XCTAssertEqual(setting(200_000, in: ours), .unchanged)
    }

    func testAForeignValueIsNotTouched() {
        let text = "model_auto_compact_token_limit = 100000\n"
        XCTAssertEqual(setting(332_500, in: text), .foreign("100000"))
        XCTAssertEqual(removing(in: text), .foreign("100000"))
    }

    func testTheKeyInATableIsNotTheTopLevelKey() {
        let text = "model = \"gpt\"\n[profiles.fast]\nmodel_auto_compact_token_limit = 100000\n"
        XCTAssertEqual(setting(332_500, in: text), .changed(
            "model = \"gpt\"\nmodel_auto_compact_token_limit = 332500 # set by Hats\n"
                + "[profiles.fast]\nmodel_auto_compact_token_limit = 100000\n"
        ))
    }

    func testRemovingTakesOnlyOurLineAndNeverEmptiesTheFile() {
        let text = "model_auto_compact_token_limit = 332500 # set by Hats\n"
        XCTAssertEqual(removing(in: text), .changed(""))
        XCTAssertEqual(removing(in: "model = \"gpt\"\n"), .unchanged)
        XCTAssertEqual(removing(in: nil), .unchanged)
    }

    func testTheGatewayLineIsUnaffectedByTheKey() {
        let text = "openai_base_url = \"http://127.0.0.1:8788/s3cr3t/codex\"\n"
        XCTAssertEqual(setting(332_500, in: text), .changed(text + "model_auto_compact_token_limit = 332500 # set by Hats\n"))
        XCTAssertNil(CodexConfigText.find(in: "model_auto_compact_token_limit = 1 # set by Hats\n"))
    }

    func testTheSmallestRecentWindowWins() throws {
        try writeWindow("big-1", 475_000)
        try writeWindow("small-1", 272_000, age: 3600)
        try writeWindow("old-1", 128_000, age: CodexCompactLimit.windowAge + 60)
        try "{\"window\": \"big\"}".write(to: windows.appendingPathComponent("bad-1.json"), atomically: true, encoding: .utf8)
        try "{\"window\": 1}".write(to: windows.appendingPathComponent(".tmp-x.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(CodexCompactLimit.smallestWindow(in: windows, now: Date()), 272_000)
        XCTAssertNil(CodexCompactLimit.smallestWindow(in: folder.appendingPathComponent("none"), now: Date()))
    }

    func testWindowFilesOlderThanSevenDaysCountForNothing() throws {
        try writeWindow("old-1", 475_000, age: CodexCompactLimit.windowAge + 60)
        XCTAssertNil(CodexCompactLimit.smallestWindow(in: windows, now: Date()))
    }
}
