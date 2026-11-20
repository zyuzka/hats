import XCTest
@testable import Hats

final class CodexGatewayRunTests: XCTestCase {
    private let home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let secret = String(repeating: "7a", count: 32)
    private lazy var run = CodexGatewayRun(broker: CodexGatewayDesk(
        desk: CodexDesk(world: server.world(home: home, keychain: keychain)),
        state: CodexGatewayState()
    ))

    override func tearDown() {
        run.stop()
        try? FileManager.default.removeItem(at: home.url)
    }

    private var config: String? { try? String(contentsOf: home.config, encoding: .utf8) }

    func testServingWritesTheKeyForTheBoundPortAndRetiringRemovesTheFileHatsCreated() throws {
        var created = false

        XCTAssertTrue(run.serve(port: 0, secret: secret, recheck: false, createdByHats: &created).isServing)

        let port = try XCTUnwrap(run.servingPort)
        XCTAssertEqual(config, "openai_base_url = \"http://127.0.0.1:\(port)/\(secret)/codex\"\n")
        XCTAssertTrue(created, "Hats made the file, so Hats may remove it")

        run.retire(secret: secret, createdByHats: &created)

        XCTAssertFalse(FileManager.default.fileExists(atPath: home.config.path), "the file Hats created is gone")
        XCTAssertFalse(created)
        XCTAssertFalse(run.isServing)
    }

    func testRetiringLeavesTheRestOfAFileHatsDidNotCreate() throws {
        let original = "model = \"x\"\n\n[tui]\nfullscreen = true\n"
        try original.write(to: home.config, atomically: true, encoding: .utf8)
        var created = false

        run.serve(port: 0, secret: secret, recheck: false, createdByHats: &created)
        XCTAssertTrue(config?.contains("openai_base_url") == true)
        XCTAssertFalse(created)
        run.retire(secret: secret, createdByHats: &created)

        XCTAssertEqual(config, original)
    }

    func testAForeignKeyIsToldInThePanelAndTheGatewayStillListens() throws {
        let theirs = "openai_base_url = \"https://proxy.example/v1\"\n"
        try theirs.write(to: home.config, atomically: true, encoding: .utf8)
        var created = false

        XCTAssertTrue(run.serve(port: 0, secret: secret, recheck: false, createdByHats: &created).isServing)

        XCTAssertEqual(run.configNote, HatsCopy.codexConfigForeign(home.config.path))
        XCTAssertTrue(run.configNote?.contains("left it alone") == true)
        XCTAssertEqual(config, theirs)
        run.retire(secret: secret, createdByHats: &created)
        XCTAssertEqual(config, theirs, "stopping leaves the other line alone too")
    }

    func testTheFirstStartIsToldOnceAndNeverAgain() throws {
        var settings = AppSettings()
        XCTAssertTrue(CodexGatewayRun.isTheFirstStart(told: &settings.hasToldToRestartCodexWindows))
        XCTAssertTrue(settings.hasToldToRestartCodexWindows)
        XCTAssertFalse(CodexGatewayRun.isTheFirstStart(told: &settings.hasToldToRestartCodexWindows))

        var reloaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(CodexGatewayRun.isTheFirstStart(told: &reloaded.hasToldToRestartCodexWindows),
                       "the second time is not the first even after Hats starts again")
    }

    func testRemovingTheLastCodexHatAsksWhenThreadsGoThroughTheGateway() {
        var only = Account(id: "c1", email: "work@example.com", browser: nil)
        only.tool = .codex
        var other = Account(id: "c2", email: "personal@example.com", browser: nil)
        other.tool = .codex
        let claude = Account(id: "a1", email: "work@example.com", browser: nil)

        guard case .ask(let cost) = GatewayStopDecision.ofRemoving(only, codexHats: [only], isServing: true,
                                                                   threads: 2) else {
            return XCTFail("removing the last Codex hat stops the gateway the threads go through")
        }
        XCTAssertTrue(cost.contains("2 Codex threads"), cost)
        XCTAssertEqual(GatewayStopDecision.ofRemoving(only, codexHats: [only, other], isServing: true, threads: 2),
                       .proceed, "another Codex hat keeps the gateway running")
        XCTAssertEqual(GatewayStopDecision.ofRemoving(only, codexHats: [only], isServing: true, threads: 0), .proceed)
        XCTAssertEqual(GatewayStopDecision.ofRemoving(only, codexHats: [only], isServing: false, threads: 2), .proceed)
        XCTAssertEqual(GatewayStopDecision.ofRemoving(claude, codexHats: [only], isServing: true, threads: 2), .proceed)
    }
}
