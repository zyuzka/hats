import XCTest
@testable import Hats

final class CodexGatewayDeskTests: XCTestCase {
    private let home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let state = CodexGatewayState()
    private let spare = CodexFixture.Person(user: "user-spare", account: "acct-spare", email: "spare@example.com")
    private let work = CodexFixture.ticket("hat-work", CodexFixture.work)
    private let personal = CodexFixture.ticket("hat-personal", CodexFixture.personal)
    private lazy var third = CodexFixture.ticket("hat-spare", spare)
    private lazy var desk = CodexDesk(world: server.world(home: home, keychain: keychain))
    private lazy var broker = CodexGatewayDesk(desk: desk, state: state)
    private var toldAllAtLimit = 0
    private var worn: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        let workLive = CodexFixture.login(CodexFixture.work, refresh: "work-1")
        try workLive.write(to: home.auth)
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(CodexFixture.personal, refresh: "p-1")
        keychain.contents[Slot.codexParked(third.id)] = CodexFixture.login(spare, refresh: "s-1")
        broker.hats = CodexGatewayHats(all: [work, personal, third], candidates: [work, personal, third])
        broker.onAllAtLimit = { [unowned self] in toldAllAtLimit += 1 }
        broker.onWorn = { [unowned self] id, _, _ in worn.append(id) }
        broker.noticeTheLiveFile()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
    }

    private func limit(_ refused: CodexGatewayLogin?, tried: Set<String>) -> CodexGatewayLogin? {
        guard let refused else { return nil }
        var answer: CodexGatewayLogin?
        broker.usageLimit(refused, tried: tried.union([refused.hatID])) { answer = $0 }
        return answer
    }

    private var liveOwner: CodexOwner? { (try? Data(contentsOf: home.auth)).flatMap { CodexAuth(data: $0)?.owner } }

    func testTheLiveFileGivesTheGatewayItsLogin() {
        XCTAssertEqual(state.login?.hatID, work.id)
        XCTAssertEqual(state.login?.accountID, CodexFixture.work.account)
    }

    func testALimitOnTheCurrentShiftWearsTheNextHatInTheListAndTheGatewayFollowsAtOnce() {
        let before = state.login

        let next = limit(before, tried: [])

        XCTAssertEqual(next?.hatID, personal.id)
        XCTAssertEqual(state.login?.hatID, personal.id, "the gateway's login moved with the live file")
        XCTAssertNotEqual(next?.shift, before?.shift)
        XCTAssertEqual(liveOwner, CodexFixture.personal.owner)
        XCTAssertEqual(worn, [personal.id])
    }

    func testAHatOnVacationOrNeedingASignInIsSkipped() {
        let sleepy = CodexTicket(id: personal.id, owner: personal.owner, title: "p", needsSignIn: true)
        broker.hats = CodexGatewayHats(all: [work, sleepy, third], candidates: [work, sleepy, third])
        XCTAssertEqual(limit(state.login, tried: [])?.hatID, third.id)

        broker.hats = CodexGatewayHats(all: [work, personal, third], candidates: [work, third])
        state.wear(hatID: work.id, auth: CodexFixture.login(CodexFixture.work, refresh: "w"))
        XCTAssertEqual(limit(state.login, tried: [])?.hatID, third.id, "personal is on vacation")
    }

    func testALateLimitAfterAManualChangeRetriesOnTheHatWornNowWithoutAnotherChange() throws {
        let refused = try XCTUnwrap(state.login)
        state.wear(hatID: personal.id, auth: CodexFixture.login(CodexFixture.personal, refresh: "p-1"))

        let next = limit(refused, tried: [])

        XCTAssertEqual(next?.hatID, personal.id)
        XCTAssertEqual(liveOwner, CodexFixture.work.owner, "nothing new was worn")
        XCTAssertEqual(worn, [])
    }

    func testAHatWornBackByHandThatAlreadyRefusedIsNotAskedAgain() throws {
        let onWork = try XCTUnwrap(state.login)
        let onPersonal = try XCTUnwrap(limit(onWork, tried: []))
        state.wear(hatID: work.id, auth: CodexFixture.login(CodexFixture.work, refresh: "w"))

        XCTAssertNil(limit(onPersonal, tried: [work.id]), "work refused in this request already")
        XCTAssertEqual(toldAllAtLimit, 0, "the spare hat never refused, so not every hat is at its limit")
    }

    func testOnlyWhenEveryHatRefusedIsTheUserTold() throws {
        let onWork = try XCTUnwrap(state.login)
        let onPersonal = try XCTUnwrap(limit(onWork, tried: []))
        let onSpare = try XCTUnwrap(limit(onPersonal, tried: [work.id]))
        XCTAssertEqual(toldAllAtLimit, 0)

        XCTAssertNil(limit(onSpare, tried: [work.id, personal.id]))
        XCTAssertEqual(toldAllAtLimit, 1)
        XCTAssertNil(limit(state.login, tried: [work.id, personal.id]))
        XCTAssertEqual(toldAllAtLimit, 1, "told once, not on every refused request")
    }

    func testWearingByHandMovesTheGatewayBeforeTheParkedHatIsRenewed() throws {
        var loginWhenRenewing: String?
        server.duringSend = { [unowned self] in loginWhenRenewing = state.login?.hatID }
        server.renewed(["access_token": "a", "refresh_token": "work-2"])

        desk.wear(personal, among: [work, personal, third]) { _, _ in }

        XCTAssertEqual(state.login?.hatID, personal.id)
        XCTAssertEqual(loginWhenRenewing, personal.id)
    }

    func testAnUnauthorizedWithANewerTokenInTheFileTakesItWithoutRenewing() throws {
        let refused = try XCTUnwrap(state.login)
        let newer = CodexFixture.login(CodexFixture.work, refresh: "work-from-codex")
        try newer.write(to: home.auth)
        var recovery: CodexGatewayRecovery?

        broker.unauthorized(refused) { recovery = $0 }

        guard case .retry(let answer) = recovery else { return XCTFail("no retry: \(String(describing: recovery))") }
        XCTAssertEqual(answer.accessToken, CodexAuth(data: newer)?.accessToken)
        XCTAssertEqual(answer.shift, refused.shift, "a new token of the same hat is not a change of hat")
        XCTAssertEqual(server.sent.count, 0)
    }

    func testTheWornHatRenewedByHatsIsWhatTheGatewaySendsNext() throws {
        let due = CodexFixture.login(CodexFixture.work, refresh: "work-1", expiresAt: CodexFixture.now.addingTimeInterval(60))
        try due.write(to: home.auth)
        broker.noticeTheLiveFile()
        let shift = state.login?.shift
        server.renewed(["access_token": "work-access-2", "refresh_token": "work-2"])

        broker.renewTheWorn(work)

        XCTAssertEqual(state.login?.accessToken, "work-access-2")
        XCTAssertEqual(state.login?.shift, shift, "a renewal is not a change of hat")
        XCTAssertEqual(CodexFixture.refreshToken(in: try? Data(contentsOf: home.auth)), "work-2")
    }
}
