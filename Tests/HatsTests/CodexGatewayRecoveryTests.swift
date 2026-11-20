import XCTest
@testable import Hats

final class CodexGatewayRecoveryTests: XCTestCase {
    private let home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let state = CodexGatewayState()
    private let work = CodexFixture.ticket("hat-work", CodexFixture.work)
    private var needsSignIn: [String] = []
    private lazy var broker: CodexGatewayDesk = {
        var world = server.world(home: home, keychain: keychain)
        world.pause = { _ in }
        world.waitForCodex = 1
        let broker = CodexGatewayDesk(desk: CodexDesk(world: world), state: state)
        broker.hats = CodexGatewayHats(all: [work], candidates: [work])
        broker.onNeedsSignIn = { [unowned self] id, _ in needsSignIn.append(id) }
        return broker
    }()

    override func setUpWithError() throws {
        try super.setUpWithError()
        try CodexFixture.login(CodexFixture.work, refresh: "work-1").write(to: home.auth)
        broker.noticeTheLiveFile()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
    }

    private func recover() throws -> CodexGatewayRecovery? {
        let refused = try XCTUnwrap(state.login)
        var recovery: CodexGatewayRecovery?
        broker.unauthorized(refused) { recovery = $0 }
        return recovery
    }

    func testTheSameTokenRefusedIsRenewedOnceByForceAndTheRequestRetriesOnTheNewOne() throws {
        server.renewed(["access_token": "work-access-2", "refresh_token": "work-2"])

        guard case .retry(let login) = try recover() else { return XCTFail("no retry") }

        XCTAssertEqual(server.sentRefreshTokens, ["work-1"], "the token was not due, the 401 forced it")
        XCTAssertEqual(login.accessToken, "work-access-2")
        XCTAssertEqual(state.login?.accessToken, "work-access-2")
        XCTAssertEqual(needsSignIn, [])
    }

    func testANetworkFailureWhileRenewingIsNotASignIn() throws {
        XCTAssertEqual(try recover(), .unreachable)
        XCTAssertEqual(needsSignIn, [], "the hat is not marked for a failure of the network")
    }

    func testA401ForAHatNoLongerWornRetriesOnTheWornOneWithoutRenewing() throws {
        let refused = try XCTUnwrap(state.login)
        state.wear(hatID: "hat-personal", auth: CodexFixture.login(CodexFixture.personal, refresh: "p-1"))
        var recovery: CodexGatewayRecovery?

        broker.unauthorized(refused) { recovery = $0 }

        XCTAssertEqual(recovery, state.login.map(CodexGatewayRecovery.retry))
        XCTAssertEqual(server.sent.count, 0)
    }

    func testALiveLoginOfAKnownHatWithoutATokenTakesTheGatewaysLoginOff() throws {
        let login = CodexFixture.login(CodexFixture.work, refresh: "work-1")
        var root = try XCTUnwrap(CodexAuth(data: login)?.root)
        var tokens = try XCTUnwrap(root["tokens"] as? [String: Any])
        tokens["access_token"] = ""
        root["tokens"] = tokens
        try CodexAuth(root: root).data().write(to: home.auth)

        broker.noticeTheLiveFile()

        XCTAssertNil(state.login, "the previous login is not sent under a file that no longer carries it")
    }

    func testARealRefusalOfTheLoginMarksTheHat() throws {
        server.answers = [(400, Data(#"{"error":"refresh_token_reused"}"#.utf8))]

        XCTAssertEqual(try recover(), .needsSignIn)
        XCTAssertEqual(needsSignIn, [work.id])
    }
}

final class CodexGatewayRenewedTests: CodexGatewayTestCase {
    private let home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let refresher = FakeCodexServer()
    private let work = CodexFixture.ticket("hat-work", CodexFixture.work)
    private var real: CodexGatewayDesk!

    override func setUpWithError() throws {
        try super.setUpWithError()
        gateway.stop()
        let due = CodexFixture.login(CodexFixture.work, refresh: "work-1", expiresAt: CodexFixture.now.addingTimeInterval(60))
        try due.write(to: home.auth)
        real = CodexGatewayDesk(desk: CodexDesk(world: refresher.world(home: home, keychain: keychain)), state: state)
        real.hats = CodexGatewayHats(all: [work], candidates: [work])
        gateway = CodexGatewayServer(port: 0, secret: secret, state: state, broker: real,
                                     upstream: URL(string: "http://127.0.0.1:\(upstream.port)/backend-api/codex")!)
        try gateway.start()
        real.noticeTheLiveFile()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
        super.tearDown()
    }

    func testAfterHatsRenewedTheWornHatTheNextTurnsGoWithTheNewLogin() {
        _ = ask()
        XCTAssertNotEqual(lastSeen?.headers["authorization"], "Bearer work-access-2")
        refresher.renewed(["access_token": "work-access-2", "refresh_token": "work-2"])

        real.renewTheWorn(work)

        _ = ask()
        XCTAssertEqual(lastSeen?.headers["authorization"], "Bearer work-access-2")
        _ = ask()
        XCTAssertEqual(lastSeen?.headers["authorization"], "Bearer work-access-2", "and the turn after it too")
        XCTAssertEqual(lastSeen?.headers["chatgpt-account-id"], CodexFixture.work.account)
    }
}
