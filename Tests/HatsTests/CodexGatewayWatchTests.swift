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

    func testAStoppedGatewayNoLongerWatches() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "work-1").write(to: home.auth)
        run.start(port: 0, secret: secret)
        run.stop()

        try CodexFixture.login(CodexFixture.personal, refresh: "personal-1").write(to: home.auth)

        XCTAssertEqual(waitForTheWornHat("hat-personal", within: 0.3), "hat-work")
    }
}
