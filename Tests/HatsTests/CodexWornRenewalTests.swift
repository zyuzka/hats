import XCTest
@testable import Hats

final class CodexWornRenewalTests: XCTestCase {
    private let home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let work = CodexFixture.ticket("hat-work", CodexFixture.work)
    private var pauses = 0
    private var duringPause: (Int) -> Void = { _ in }
    private var renameFails = false
    private lazy var desk: CodexDesk = {
        var world = server.world(home: home, keychain: keychain)
        world.home.rename = { [unowned self] from, to in
            if renameFails { throw CodexError.writeFailed("disk full") }
            try CodexHome.systemRename(from, to)
        }
        world.pause = { [unowned self] _ in
            pauses += 1
            duringPause(pauses)
        }
        return CodexDesk(world: world)
    }()

    private let dueLogin = CodexFixture.login(
        CodexFixture.work,
        refresh: "work-1",
        expiresAt: CodexFixture.now.addingTimeInterval(3600)
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        try dueLogin.write(to: home.auth)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
    }

    private func live() -> Data? { try? Data(contentsOf: home.auth) }

    private func slot() -> Data? { keychain.contents[Slot.codexParked(work.id)] }

    func testAWornHatCloseToItsExpiryIsRenewedIntoTheLiveFileAndItsSlot() throws {
        server.renewed(["access_token": "work-access-2", "refresh_token": "work-2"])

        let outcome = desk.renewWornNow(work)

        XCTAssertEqual(server.sentRefreshTokens, ["work-1"], "renewed from the live file, not from the slot")
        XCTAssertEqual(CodexFixture.refreshToken(in: live()), "work-2")
        XCTAssertEqual(CodexFixture.refreshToken(in: slot()), "work-2")
        XCTAssertEqual(outcome, .fresh(try XCTUnwrap(live())))
    }

    func testAWornHatFarFromItsExpiryIsLeftAlone() throws {
        let fresh = CodexFixture.login(CodexFixture.work, refresh: "w", expiresAt: CodexFixture.now.addingTimeInterval(5 * 86400))
        try fresh.write(to: home.auth)

        XCTAssertEqual(desk.renewWornNow(work), .notDue(fresh))
        XCTAssertEqual(server.sent.count, 0)
    }

    func testWhenCodexRenewedFirstTheFileIsNotTouchedAndItsLoginIsTaken() throws {
        let codexWrote = CodexFixture.login(CodexFixture.work, refresh: "work-codex")
        server.renewed(["access_token": "work-access-2", "refresh_token": "work-2"])
        server.duringSend = { [home] in try? codexWrote.write(to: home.auth) }

        XCTAssertEqual(desk.renewWornNow(work), .fresh(codexWrote))
        XCTAssertEqual(live(), codexWrote)
    }

    func testWhenAnotherHatIsInTheFileTheAnswerGoesOnlyToThisHatsSlot() throws {
        let personalLive = CodexFixture.login(CodexFixture.personal, refresh: "p")
        server.renewed(["access_token": "work-access-2", "refresh_token": "work-2"])
        server.duringSend = { [home] in try? personalLive.write(to: home.auth) }

        XCTAssertEqual(desk.renewWornNow(work), .elsewhere)
        XCTAssertEqual(live(), personalLive, "the live file of the other hat is not touched")
        XCTAssertEqual(CodexFixture.refreshToken(in: slot()), "work-2")
    }

    func testARefusalWhileCodexIsStillWritingWaitsForCodexAndTakesItsLogin() throws {
        let codexWrote = CodexFixture.login(CodexFixture.work, refresh: "work-codex")
        server.answers = [(400, Data(#"{"error":"refresh_token_reused"}"#.utf8))]
        duringPause = { [home] count in if count == 3 { try? codexWrote.write(to: home.auth) } }

        XCTAssertEqual(desk.renewWornNow(work), .fresh(codexWrote))
        XCTAssertEqual(pauses, 3)
    }

    func testARefusalWithNoWriteFromCodexIn30SecondsNeedsASignIn() {
        server.answers = [(400, Data(#"{"error":"refresh_token_reused"}"#.utf8))]

        XCTAssertEqual(desk.renewWornNow(work), .needsSignIn("refresh_token_reused"))
        XCTAssertEqual(Double(pauses) * CodexDesk.codexWriteStep, 30, accuracy: 0.01)
        XCTAssertEqual(live(), dueLogin)
    }

    func testAnAnswerThatCouldNotBeWrittenIsKeptAndOnlyTheWriteIsRepeated() throws {
        server.renewed(["access_token": "work-access-2", "refresh_token": "work-2"])
        renameFails = true

        guard case .failed = desk.renewWornNow(work) else { return XCTFail("the write should have failed") }
        XCTAssertEqual(live(), dueLogin)
        XCTAssertEqual(desk.heldIDs(), [work.id])

        renameFails = false
        XCTAssertEqual(desk.renewWornNow(work), .fresh(try XCTUnwrap(live())))
        XCTAssertEqual(server.sentRefreshTokens, ["work-1"], "the spent token is not sent again")
        XCTAssertEqual(CodexFixture.refreshToken(in: live()), "work-2")
        XCTAssertEqual(desk.heldIDs(), [])
    }

    func testAForcedRenewalAfterAnUnauthorizedRenewsEvenWhenNotDue() throws {
        let fresh = CodexFixture.login(CodexFixture.work, refresh: "w", expiresAt: CodexFixture.now.addingTimeInterval(5 * 86400))
        try fresh.write(to: home.auth)
        server.renewed(["access_token": "work-access-2", "refresh_token": "work-2"])

        let outcome = desk.renewWornNow(work, refused: CodexAuth(data: fresh)?.accessToken)

        XCTAssertEqual(server.sentRefreshTokens, ["w"])
        XCTAssertEqual(outcome, .fresh(try XCTUnwrap(live())))
    }
}
