import XCTest
@testable import Hats

final class CodexRenewalTests: XCTestCase {
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

    func testASlotThatDidNotTakeIsSavedAgainWithoutAskingAgain() throws {
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(
            CodexFixture.personal, refresh: "p-1", expiresAt: CodexFixture.now.addingTimeInterval(3600))
        keychain.writeFailures = [Slot.codexParked(personal.id)]
        server.renewed(["refresh_token": "p-2"])
        desk.renew([personal]) { _ in }

        keychain.writeFailures = []
        var results: [CodexRenewed] = []
        desk.renew([personal]) { results = $0 }

        XCTAssertEqual(server.sentRefreshTokens, ["p-1"])
        XCTAssertEqual(CodexFixture.refreshToken(in: slot(personal)), "p-2")
        guard case .renewed(personal.id, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(desk.heldIDs(), [])
    }

    func testOnlyAnAnswerNotSavedIsWhatAQuitLosesNotARequestInFlight() {
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(
            CodexFixture.personal, refresh: "p-1", expiresAt: CodexFixture.now)
        var seenInFlight: [String] = []
        server.duringSend = { [unowned self] in seenInFlight = self.desk.heldIDs() }
        server.renewed(["refresh_token": "p-2"])
        keychain.writeFailures = [Slot.codexParked(personal.id)]

        desk.renew([personal]) { _ in }

        XCTAssertEqual(seenInFlight, [], "a request without an answer has spent nothing yet")
        XCTAssertEqual(desk.heldIDs(), [personal.id])
        keychain.writeFailures = []
        desk.renew([personal]) { _ in }
        XCTAssertEqual(desk.heldIDs(), [])
    }

    func testOnlyAHatDueWithinADayIsRenewed() {
        let soon = CodexAuth(data: CodexFixture.login(CodexFixture.work, refresh: "r",
                                                      expiresAt: CodexFixture.now.addingTimeInterval(23 * 3600)))
        let later = CodexAuth(data: CodexFixture.login(CodexFixture.work, refresh: "r",
                                                       expiresAt: CodexFixture.now.addingTimeInterval(25 * 3600)))
        let noExpiryOld = CodexAuth(data: CodexFixture.login(CodexFixture.work, refresh: "r", expiresAt: nil,
                                                             signedInAt: CodexFixture.now.addingTimeInterval(-9 * 86_400)))
        let noExpiryNew = CodexAuth(data: CodexFixture.login(CodexFixture.work, refresh: "r", expiresAt: nil,
                                                             signedInAt: CodexFixture.now.addingTimeInterval(-7 * 86_400)))

        XCTAssertTrue(CodexRenewal.isDue(soon!, at: CodexFixture.now))
        XCTAssertFalse(CodexRenewal.isDue(later!, at: CodexFixture.now))
        XCTAssertTrue(CodexRenewal.isDue(noExpiryOld!, at: CodexFixture.now))
        XCTAssertFalse(CodexRenewal.isDue(noExpiryNew!, at: CodexFixture.now))
    }

    func testARenewalThatNamesAnotherAccountIsNotWritten() {
        let stored = CodexFixture.login(CodexFixture.work, refresh: "w", expiresAt: CodexFixture.now)
        keychain.contents[Slot.codexParked(work.id)] = stored
        server.renewed([
            "id_token": CodexFixture.idToken(user: "user-x", account: "acct-x", email: "x@example.com"),
            "refresh_token": "w-2",
        ])

        var results: [CodexRenewed] = []
        desk.renew([work]) { results = $0 }

        XCTAssertEqual(results, [.needsSignIn(work.id, "the renewed login names another account")],
                       "the stored refresh token is spent, so the hat needs a sign-in")
        XCTAssertEqual(slot(work), stored)
    }

    func testARefusedRefreshTokenNeedsASignInAndIsNotRetried() {
        for (status, body) in [
            (400, #"{"error":{"code":"refresh_token_reused"}}"#),
            (401, #"{"error":"whatever"}"#),
            (400, #"{"error":"refresh_token_expired"}"#),
            (400, #"{"code":"refresh_token_invalidated"}"#),
            (400, #"{"error":"invalid_grant"}"#),
        ] {
            XCTAssertEqual(CodexRenewal.answer(status: status, body: Data(body.utf8)).isNeedsSignIn, true, body)
        }
        keychain.contents[Slot.codexParked(work.id)] = CodexFixture.login(CodexFixture.work, refresh: "w",
                                                                          expiresAt: CodexFixture.now)
        server.answers = [(400, Data(#"{"error":{"code":"refresh_token_reused"}}"#.utf8))]

        var results: [CodexRenewed] = []
        desk.renew([work]) { results = $0 }

        XCTAssertEqual(results, [.needsSignIn(work.id, "refresh_token_reused")])
        desk.renew([CodexTicket(id: work.id, owner: work.owner, title: work.title, needsSignIn: true)]) { _ in }
        XCTAssertEqual(server.sent.count, 1)
    }

    func testANetworkFailureWaitsForTheBackoff() {
        keychain.contents[Slot.codexParked(work.id)] = CodexFixture.login(CodexFixture.work, refresh: "w",
                                                                          expiresAt: CodexFixture.now)

        desk.renew([work]) { _ in }
        desk.renew([work]) { _ in }

        XCTAssertEqual(server.sent.count, 1, "the second poll falls inside the wait RenewalBackoff sets")
    }
}

private extension CodexRenewal.Answer {
    var isNeedsSignIn: Bool {
        if case .needsSignIn = self { return true }
        return false
    }
}
