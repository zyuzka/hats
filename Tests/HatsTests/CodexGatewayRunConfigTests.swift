import XCTest
@testable import Hats

final class CodexGatewayRunConfigTests: XCTestCase {
    private let home = CodexFixture.home()
    private let secret = String(repeating: "7a", count: 32)
    private lazy var run = CodexGatewayRun(broker: CodexGatewayDesk(
        desk: CodexDesk(world: FakeCodexServer().world(home: home, keychain: FakeKeychain())),
        state: CodexGatewayState()
    ))
    private var created = false

    override func tearDown() {
        run.stop()
        try? FileManager.default.removeItem(at: home.url)
    }

    private var config: String? { try? String(contentsOf: home.config, encoding: .utf8) }

    private static func freePort() throws -> Int {
        let probe = NIOTestListener()
        try probe.start()
        defer { probe.stop() }
        return probe.port
    }

    func testMovingThePortNamesTheNewOneAndTheOldListenerStops() throws {
        let first = try Self.freePort()
        let second = try Self.freePort()
        XCTAssertTrue(run.serve(port: first, secret: secret, recheck: false, createdByHats: &created).isServing)
        XCTAssertTrue(config?.contains(":\(first)/") == true)

        XCTAssertTrue(run.serve(port: second, secret: secret, recheck: false, createdByHats: &created).isServing)

        XCTAssertEqual(config, "openai_base_url = \"http://127.0.0.1:\(second)/\(secret)/codex\"\n")
        XCTAssertThrowsError(try RawHTTPClient.Connection(port: first), "the old port no longer listens")
    }

    func testALineSomeoneDeletedIsWrittenAgainOnTheNextCheck() throws {
        run.serve(port: 0, secret: secret, recheck: false, createdByHats: &created)
        try "model = \"x\"\n".write(to: home.config, atomically: true, encoding: .utf8)

        run.serve(port: 0, secret: secret, recheck: true, createdByHats: &created)

        XCTAssertTrue(config?.contains("openai_base_url") == true, "the timer puts the line back")
        XCTAssertTrue(config?.hasPrefix("model = \"x\"\n") == true)
    }

    func testARemovalThatFailsAtQuitIsTriedAgain() throws {
        run.serve(port: 0, secret: secret, recheck: false, createdByHats: &created)
        try "model = \"x\"\n".write(to: home.config, atomically: true, encoding: .utf8)
        run.serve(port: 0, secret: secret, recheck: true, createdByHats: &created)
        var file = CodexConfigFile(url: home.config)
        var failures = 1
        file.rename = { from, to in
            if failures > 0 {
                failures -= 1
                throw CodexError.writeFailed("busy")
            }
            try CodexHome.systemRename(from, to)
        }
        run.configFile = file

        run.retire(secret: secret, createdByHats: &created)

        XCTAssertEqual(config, "model = \"x\"\n", "the second try removed the line")
        XCTAssertEqual(failures, 0)
    }

    func testAValueOverSeveralLinesOnTopIsLeftAloneAndToldInThePanel() throws {
        let text = "model = \"x\"\nprojects = [\n  \"a\",\n]\n[tui]\nx = 1\n"
        try text.write(to: home.config, atomically: true, encoding: .utf8)

        XCTAssertTrue(run.serve(port: 0, secret: secret, recheck: false, createdByHats: &created).isServing)

        XCTAssertEqual(config, text)
        XCTAssertEqual(run.configNote, HatsCopy.codexConfigUnsupported(home.config.path))
    }

    func testALineHatsCannotRemoveIsNotCountedAsRemovedAndIsToldInThePanel() throws {
        try "model = \"x\"\n".write(to: home.config, atomically: true, encoding: .utf8)
        XCTAssertTrue(run.serve(port: 0, secret: secret, recheck: false, createdByHats: &created).isServing)
        let written = try XCTUnwrap(config)
        try ("projects = [\n  \"a\",\n]\n" + written).write(to: home.config, atomically: true, encoding: .utf8)

        XCTAssertFalse(run.hasRemovedConfig(secret: secret, createdByHats: &created),
                       "a value over several lines on top stops Hats from removing its own line")
        XCTAssertEqual(run.configNote, HatsCopy.codexConfigNotRemoved(home.config.path))
        run.retire(secret: secret, createdByHats: &created)

        XCTAssertFalse(run.isServing)
        XCTAssertEqual(run.configNote, HatsCopy.codexConfigNotRemoved(home.config.path),
                       "the note stays after the stop, so the panel says why Codex cannot connect")
        XCTAssertTrue(config?.contains("openai_base_url") == true)
    }

    func testTheSettingsKeepThePortAndWhetherHatsCreatedTheFile() throws {
        var settings = AppSettings()
        settings.codexGatewayPort = 9123
        settings.codexConfigCreatedByHats = true
        settings.hasCodexHats = true
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.codexGatewayPort, 9123)
        XCTAssertTrue(back.codexConfigCreatedByHats)
        XCTAssertTrue(back.hasCodexHats)
    }

    func testAWrongTypedCodexFieldKeepsEveryOtherSetting() throws {
        let json = #"""
            {"gatewayPort": 9000, "showsHatNameInTheMenuBar": false, "codexGatewayPort": "x",
             "isCodexGatewayEnabled": "yes", "codexGatewaySecret": 7, "codexConfigCreatedByHats": "no",
             "hasToldToRestartCodexWindows": 1, "hasCodexHats": "true"}
            """#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.gatewayPort, 9000)
        XCTAssertFalse(settings.showsHatNameInTheMenuBar)
        XCTAssertEqual(settings.codexGatewayPort, 8788)
        XCTAssertNil(settings.isCodexGatewayEnabled)
        XCTAssertNil(settings.codexGatewaySecret)
        XCTAssertFalse(settings.codexConfigCreatedByHats)
        XCTAssertFalse(settings.hasCodexHats)
    }

    func testTheGatewayIsWantedByOneRule() {
        XCTAssertFalse(CodexGatewayWanted.isWanted(hasCodexHats: false, enabled: true))
        XCTAssertFalse(CodexGatewayWanted.isWanted(hasCodexHats: false, enabled: nil))
        XCTAssertTrue(CodexGatewayWanted.isWanted(hasCodexHats: true, enabled: nil))
        XCTAssertFalse(CodexGatewayWanted.isWanted(hasCodexHats: true, enabled: false))
        XCTAssertTrue(CodexGatewayWanted.isWanted(hasCodexHats: true, enabled: true))
    }
}
