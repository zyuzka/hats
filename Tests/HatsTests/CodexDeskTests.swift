import XCTest
@testable import Hats

final class CodexDeskTests: XCTestCase {
    private let home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let work = CodexFixture.ticket("hat-work", CodexFixture.work)
    private let personal = CodexFixture.ticket("hat-personal", CodexFixture.personal)
    private lazy var desk = CodexDesk(world: server.world(home: home, keychain: keychain))

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
    }

    private func slot(_ ticket: CodexTicket) -> Data? { keychain.contents[Slot.codexParked(ticket.id)] }

    private func live() -> Data? { try? Data(contentsOf: home.auth) }

    private func wear(_ target: CodexTicket) -> (Result<CodexWorn, Error>, [CodexRenewed]) {
        var outcome: (Result<CodexWorn, Error>, [CodexRenewed])?
        desk.wear(target, among: [work, personal]) { outcome = ($0, $1) }
        return outcome ?? (.failure(CodexError.noOwner), [])
    }

    func testWearingParksTheLiveLoginReadsBackAndRenewsTheHatThatCameOff() throws {
        let liveWork = CodexFixture.login(CodexFixture.work, refresh: "work-live")
        let personalLogin = CodexFixture.login(CodexFixture.personal, refresh: "personal-1")
        try liveWork.write(to: home.auth)
        keychain.contents[Slot.codexParked(work.id)] = CodexFixture.login(CodexFixture.work, refresh: "work-stale")
        keychain.contents[Slot.codexParked(personal.id)] = personalLogin
        server.renewed(["access_token": "work-access-2", "refresh_token": "work-2"])

        let (result, renewed) = wear(personal)

        XCTAssertEqual(try result.get(), .worn(target: personal.id, outgoing: work.id, parked: liveWork))
        XCTAssertEqual(live(), personalLogin)
        XCTAssertEqual(server.sentRefreshTokens, ["work-live"],
                       "the hat that came off is renewed at once, from the login it was wearing")
        XCTAssertEqual(CodexFixture.refreshToken(in: slot(work)), "work-2")
        XCTAssertEqual(renewed.count, 1)
        XCTAssertEqual(CodexAuth(data: try XCTUnwrap(slot(work)))?.tokens["login_owner_id"] as? String,
                       "owner-work-live", "the renewal keeps every field it did not bring")
    }

    func testAMissingLiveFileIsCreatedWithTheTarget() throws {
        let personalLogin = CodexFixture.login(CodexFixture.personal, refresh: "p")
        keychain.contents[Slot.codexParked(personal.id)] = personalLogin

        XCTAssertEqual(try wear(personal).0.get(), .worn(target: personal.id, outgoing: nil, parked: nil))
        XCTAssertEqual(live(), personalLogin)
    }

    func testALiveLoginOfNoHatIsRefusedAndKept() throws {
        let stranger = CodexFixture.Person(user: "user-x", account: "acct-x", email: "x@example.com")
        let theirs = CodexFixture.login(stranger, refresh: "x")
        try theirs.write(to: home.auth)
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(CodexFixture.personal, refresh: "p")

        XCTAssertThrowsError(try wear(personal).0.get()) {
            XCTAssertEqual($0 as? CodexError, .foreignLogin("x@example.com"))
        }
        XCTAssertEqual(live(), theirs)
        XCTAssertEqual(keychain.writes.count, 0)
    }

    func testAWearWaitsForTheRenewalAndWritesTheNewLogin() throws {
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(
            CodexFixture.personal, refresh: "p-1", expiresAt: CodexFixture.now.addingTimeInterval(3600))
        keychain.writeFailures = [Slot.codexParked(personal.id)]
        server.renewed(["access_token": "p-access-2", "refresh_token": "p-2"])

        var results: [CodexRenewed] = []
        desk.renew([personal]) { results = $0 }
        XCTAssertEqual(results, [.notSaved(personal.id)])

        XCTAssertEqual(try wear(personal).0.get(), .worn(target: personal.id, outgoing: nil, parked: nil))
        XCTAssertEqual(CodexFixture.refreshToken(in: live()), "p-2", "the answer held in memory is what is worn")
        XCTAssertEqual(server.sentRefreshTokens, ["p-1"], "and the old token was not sent again")
    }

    func testTheWornHatIsNeverRenewed() {
        keychain.contents[Slot.codexParked(work.id)] = CodexFixture.login(CodexFixture.work, refresh: "w")
        desk.noteWorn(work.id)

        desk.renew([work], forcing: [work.id]) { _ in }

        XCTAssertEqual(server.sent.count, 0)
    }

    func testAHatThatWasRenewingWhenItCameOffSignsInAgainOnReuse() throws {
        let liveWork = CodexFixture.login(CodexFixture.work, refresh: "work-last-read")
        try liveWork.write(to: home.auth)
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(CodexFixture.personal, refresh: "p")
        server.answers = [(400, Data(#"{"error":{"code":"refresh_token_reused"}}"#.utf8))]

        let (_, renewed) = wear(personal)

        XCTAssertEqual(slot(work), liveWork, "the slot keeps the last login read from the file")
        XCTAssertEqual(renewed, [.needsSignIn(work.id, "refresh_token_reused")])
    }
}
