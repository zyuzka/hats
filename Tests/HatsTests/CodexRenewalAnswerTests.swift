import XCTest
@testable import Hats

final class CodexRenewalAnswerTests: XCTestCase {
    private let home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let work = CodexFixture.ticket("hat-work", CodexFixture.work)
    private lazy var desk = CodexDesk(world: server.world(home: home, keychain: keychain))

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
    }

    private func renew() -> [CodexRenewed] {
        var results: [CodexRenewed] = []
        desk.renew([work]) { results = $0 }
        return results
    }

    func testAnInvalidGrantMeansTheParkedHatNeedsASignIn() {
        keychain.contents[Slot.codexParked(work.id)] = CodexFixture.login(CodexFixture.work, refresh: "w",
                                                                          expiresAt: CodexFixture.now)
        server.answers = [(400, Data(#"{"error":"invalid_grant","error_description":"dead"}"#.utf8))]

        XCTAssertEqual(renew(), [.needsSignIn(work.id, "invalid_grant")])
    }

    func testAnAnswerThatCouldNotBeEncodedIsKeptAndOnlyTheSaveIsRepeated() throws {
        keychain.contents[Slot.codexParked(work.id)] = CodexFixture.login(CodexFixture.work, refresh: "w-1",
                                                                          expiresAt: CodexFixture.now)
        server.renewed(["access_token": "w-access-2", "refresh_token": "w-2"])
        desk.encode = { _ in throw CodexError.noOwner }

        XCTAssertEqual(renew(), [.notSaved(work.id)])
        XCTAssertEqual(desk.heldIDs(), [work.id], "the server has rotated the token: a quit now loses it")

        desk.encode = { try $0.data() }
        guard case .renewed(work.id, _)? = renew().first else { return XCTFail("not saved on the retry") }
        XCTAssertEqual(server.sentRefreshTokens, ["w-1"], "the spent token is not sent again")
        XCTAssertEqual(CodexFixture.refreshToken(in: keychain.contents[Slot.codexParked(work.id)]), "w-2")
        XCTAssertEqual(desk.heldIDs(), [])
    }
}
