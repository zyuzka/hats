import XCTest
@testable import Hats

final class CodexGatewayWatchTests: XCTestCase {
    private let home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let secret = String(repeating: "4d", count: 32)
    private let state = CodexGatewayState()
    private lazy var run: CodexGatewayRun = {
        let broker = CodexGatewayDesk(
            desk: CodexDesk(world: server.world(home: home, keychain: keychain)),
            state: state
        )
        let work = CodexFixture.ticket("hat-work", CodexFixture.work)
        let personal = CodexFixture.ticket("hat-personal", CodexFixture.personal)
        broker.hats = CodexGatewayHats(all: [work, personal], candidates: [work, personal])

        return CodexGatewayRun(broker: broker, watchEvery: 0.05)
    }()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let override = ProcessInfo.processInfo.environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(
            override.isEmpty,
            "starting and stopping the gateway writes to the journal, and without HATS_STATE_HOME that is "
                + "the developer's own operations.log"
        )
    }

    override func tearDown() {
        run.stop()
        try? FileManager.default.removeItem(at: home.url)
        super.tearDown()
    }

    private func waitForTheWornHat(_ id: String, within seconds: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if state.login?.hatID == id { return id }
            Thread.sleep(forTimeInterval: 0.02)
        }

        return state.login?.hatID
    }

    func testTheDefaultWatchIsEveryTwoSeconds() {
        XCTAssertEqual(CodexGatewayRun.watchEveryByDefault, 2)
    }

    func testALoginChangedPastHatsReachesTheGateway() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "work-1").write(to: home.auth)

        XCTAssertEqual(run.start(port: 0, secret: secret), .running)
        XCTAssertEqual(state.login?.hatID, "hat-work", "the start reads the live file once")

        try CodexFixture.login(CodexFixture.personal, refresh: "personal-1").write(to: home.auth)

        XCTAssertEqual(
            waitForTheWornHat("hat-personal", within: 0.9),
            "hat-personal",
            "a sign-in made in the Codex window, not through Hats, reaches the gateway on the next look"
        )
    }

    func testAHatAddedForTheLoginAlreadyInTheFileIsWornWithoutAChangeOfTheFile() throws {
        let broker = CodexGatewayDesk(
            desk: CodexDesk(world: server.world(home: home, keychain: keychain)),
            state: state
        )
        let work = CodexFixture.ticket("hat-work", CodexFixture.work)
        let personal = CodexFixture.ticket("hat-personal", CodexFixture.personal)
        broker.hats = CodexGatewayHats(all: [work], candidates: [work])
        let own = CodexGatewayRun(broker: broker, watchEvery: 0.05)
        defer { own.stop() }
        try CodexFixture.login(CodexFixture.personal, refresh: "personal-1").write(to: home.auth)
        XCTAssertEqual(own.start(port: 0, secret: secret), .running)
        XCTAssertNil(state.login, "Codex is signed in to an account Hats does not know yet")

        broker.hats = CodexGatewayHats(all: [work, personal], candidates: [work, personal])
        XCTAssertEqual(own.start(port: 0, secret: secret), .running)

        XCTAssertEqual(state.login?.hatID, "hat-personal",
                       "adding the hat does not touch auth.json, so the watch alone would never see it")
    }

    func testAStoppedGatewayNoLongerWatches() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "work-1").write(to: home.auth)
        run.start(port: 0, secret: secret)
        try CodexFixture.login(CodexFixture.personal, refresh: "personal-1").write(to: home.auth)
        XCTAssertEqual(
            waitForTheWornHat("hat-personal", within: 0.9),
            "hat-personal",
            "the watch runs before the stop, so the check below is about the stop"
        )

        run.stop()
        try CodexFixture.login(CodexFixture.work, refresh: "work-2").write(to: home.auth)

        XCTAssertEqual(waitForTheWornHat("hat-work", within: 0.3), "hat-personal")
    }
}
