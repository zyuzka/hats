import XCTest
@testable import Hats

final class CodexWearRaceTests: XCTestCase {
    private var home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let state = CodexGatewayState()
    private let spare = CodexFixture.Person(user: "user-spare", account: "acct-spare", email: "spare@example.com")
    private let work = CodexFixture.ticket("hat-work", CodexFixture.work)
    private let personal = CodexFixture.ticket("hat-personal", CodexFixture.personal)
    private lazy var third = CodexFixture.ticket("hat-spare", spare)
    private var renameFails = false

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
        super.tearDown()
    }

    private func makeDesk() -> CodexDesk {
        var world = server.world(home: home, keychain: keychain)
        world.home.rename = { [unowned self] from, to in
            if renameFails { throw CodexError.writeFailed("disk full") }
            try CodexHome.systemRename(from, to)
        }
        return CodexDesk(world: world)
    }

    private func live() throws -> Data { try Data(contentsOf: home.auth) }

    func testALoginRenewedButNotYetWrittenIsParkedWhenTheHatComesOff() throws {
        let due = CodexFixture.login(
            CodexFixture.work,
            refresh: "work-1",
            expiresAt: CodexFixture.now.addingTimeInterval(3600)
        )
        try due.write(to: home.auth)
        keychain.contents[Slot.codexParked(work.id)] = due
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(CodexFixture.personal, refresh: "p-1")
        let desk = makeDesk()
        desk.noteWornHere(work.id)
        server.renewed(["access_token": "work-access-2", "refresh_token": "work-2"])
        renameFails = true
        guard case .failed = desk.renewWornNow(work) else { return XCTFail("the write of the renewed login fails") }
        XCTAssertEqual(desk.heldIDs(), [work.id], "the renewed login waits in memory")
        renameFails = false
        server.answers = [(400, Data(#"{"error":"refresh_token_reused"}"#.utf8))]

        var worn: Result<CodexWorn, Error>?
        desk.wear(personal, among: [work, personal]) { result, _ in worn = result }

        XCTAssertNotNil(try worn?.get())
        XCTAssertEqual(CodexFixture.refreshToken(in: keychain.contents[Slot.codexParked(work.id)]), "work-2",
                       "the parked hat keeps the renewed login, not the one the server already spent")
        XCTAssertEqual(server.sentRefreshTokens.filter { $0 == "work-1" }.count, 1, "a spent token is never sent again")
    }

    func testSigningAHatInAgainLeavesAnotherAccountTheFileWearsAlone() throws {
        let personalLive = CodexFixture.login(CodexFixture.personal, refresh: "p-live")
        try personalLive.write(to: home.auth)
        let fresh = CodexFixture.login(CodexFixture.work, refresh: "fresh")
        let desk = makeDesk()
        var outcome: (stored: Bool, worn: Result<CodexWorn?, Error>)?

        desk.relogin(work, with: fresh, isWorn: true, among: [work, personal]) { outcome = ($0, $1) }

        let done = try XCTUnwrap(outcome)
        XCTAssertTrue(done.stored)
        XCTAssertNil(try done.worn.get(), "Hats remembered the hat as worn, but the file says otherwise now")
        XCTAssertEqual(try live(), personalLive, "a sign-in again never switches the worn account by itself")
        XCTAssertEqual(keychain.contents[Slot.codexParked(work.id)], fresh)
    }

    func testALimitAnsweredAfterCodexChangedTheLoginKeepsThatLoginAndRetriesOnIt() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "work-1").write(to: home.auth)
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(CodexFixture.personal, refresh: "p-1")
        keychain.contents[Slot.codexParked(third.id)] = CodexFixture.login(spare, refresh: "s-1")
        let broker = CodexGatewayDesk(desk: makeDesk(), state: state)
        broker.hats = CodexGatewayHats(all: [work, personal, third], candidates: [work, personal, third])
        broker.noticeTheLiveFile()
        let refused = try XCTUnwrap(state.login)
        XCTAssertEqual(refused.hatID, work.id)
        let signedInCodex = CodexFixture.login(CodexFixture.personal, refresh: "p-codex-login")
        try signedInCodex.write(to: home.auth)
        broker.hats = CodexGatewayHats(all: [work, third, personal], candidates: [work, third, personal])

        var answer: CodexGatewayLogin?
        broker.usageLimit(refused, tried: [work.id]) { answer = $0 }

        XCTAssertEqual(try live(), signedInCodex, "the login the user made in Codex stays")
        XCTAssertEqual(answer?.hatID, personal.id, "the request is retried on the hat Codex wears now")
        XCTAssertNil(keychain.contents[Slot.codexParked(personal.id)].flatMap {
            CodexFixture.refreshToken(in: $0) == "p-codex-login" ? $0 : nil
        }, "the new login was not parked away")
    }
}
