import XCTest
@testable import Hats

final class CodexStoreOutcomeTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("hats-outcome-\(UUID().uuidString.prefix(8))")
    private let keychain = FakeKeychain()
    private lazy var store = AccountStore(osAccount: "outcome", keychain: keychain.world(),
                                          index: folder.appendingPathComponent("accounts.json"),
                                          fetchingTokenIdentity: OfflineProfile.fetch)
    private let now = Date()

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func codex(_ person: CodexFixture.Person) throws -> Account {
        try store.addCodexHat(CodexNewHat(name: nil, email: person.email, browser: .safari),
                              login: CodexFixture.login(person, refresh: "r"), isLive: false, at: now)
    }

    private func hat(_ id: String) -> Account? { store.accounts.first { $0.id == id } }

    func testARenewalMovesTheExpiryAndKeepsTheRefusalAndTheSignIn() throws {
        let work = try codex(CodexFixture.work)
        store.noteCodexRenewals([.needsSignIn(work.id, "x")], at: now.addingTimeInterval(60))
        let refusedAt = hat(work.id)?.authRefusedAt
        let later = CodexFixture.now.addingTimeInterval(9 * 86_400)

        store.noteCodexRenewals([.renewed(work.id, CodexFixture.login(CodexFixture.work, refresh: "r2",
                                                                       expiresAt: later))])

        XCTAssertEqual(hat(work.id)?.accessExpiresAt, later)
        XCTAssertEqual(hat(work.id)?.authRefusedAt, refusedAt)
        XCTAssertEqual(hat(work.id)?.lastLoginAt, now)
    }

    func testSigningARefusedHatInAgainClearsItsBlocker() throws {
        let work = try codex(CodexFixture.work)
        store.noteCodexRenewals([.needsSignIn(work.id, "x")], at: now.addingTimeInterval(60))
        XCTAssertEqual(hat(work.id)?.blocker(), .loginRefused)

        store.noteCodexRelogin(work.id, login: CodexFixture.login(CodexFixture.work, refresh: "fresh"),
                               stored: true, outcome: nil, at: now.addingTimeInterval(120))

        XCTAssertNil(hat(work.id)?.blocker())
    }

    func testASignInThatWasNotStoredChangesNothing() throws {
        let work = try codex(CodexFixture.work)
        store.noteCodexRenewals([.needsSignIn(work.id, "x")], at: now.addingTimeInterval(60))

        store.noteCodexRelogin(work.id, login: CodexFixture.login(CodexFixture.work, refresh: "fresh"),
                               stored: false, outcome: nil, at: now.addingTimeInterval(120))

        XCTAssertEqual(hat(work.id)?.blocker(), .loginRefused)
    }

    func testAWearPutsTheHatOnAndTakesTheExpiryOfTheLoginThatCameOff() throws {
        let work = try codex(CodexFixture.work)
        let personal = try codex(CodexFixture.personal)
        let parkedExpiry = CodexFixture.now.addingTimeInterval(2 * 86_400)
        let parked = CodexFixture.login(CodexFixture.work, refresh: "live", expiresAt: parkedExpiry)

        try store.noteCodexWear(personal.id, outcome: .worn(target: personal.id, outgoing: work.id, parked: parked),
                                renewed: [])

        XCTAssertEqual(store.codexActiveID, personal.id)
        XCTAssertEqual(hat(work.id)?.accessExpiresAt, parkedExpiry)
    }
}
