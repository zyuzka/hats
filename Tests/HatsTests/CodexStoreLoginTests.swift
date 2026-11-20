import XCTest
@testable import Hats

final class CodexStoreLoginTests: XCTestCase {
    private let keychain = FakeKeychain()
    private var store: AccountStore!

    override func setUpWithError() throws {
        let override = ProcessInfo.processInfo.environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(override.isEmpty, "the store writes accounts.json through StateDirectory")
        store = AccountStore(osAccount: "codex-store-test", keychain: keychain.world())
    }

    private func newHat(_ person: CodexFixture.Person, name: String? = "work") -> CodexNewHat {
        CodexNewHat(name: name, email: person.email, browser: .safari)
    }

    func testARefusalMarksTheHatAndASignInClearsIt() throws {
        let person = CodexStoreTests.person()
        let hat = try store.addCodexHat(newHat(person), login: CodexFixture.login(person, refresh: "r"), isLive: false)

        store.noteCodexRenewals([.needsSignIn(hat.id, "refresh_token_reused")], at: Date().addingTimeInterval(60))
        XCTAssertEqual(store.accounts.first { $0.id == hat.id }?.blocker(), .loginRefused)
        XCTAssertNil(store.codexTicket(try XCTUnwrap(store.codexHats.first { $0.id == hat.id }))?.isReady)

        store.noteCodexLogin(hat.id, login: CodexFixture.login(person, refresh: "r2"), signedIn: true,
                             at: Date().addingTimeInterval(120))
        XCTAssertNil(store.accounts.first { $0.id == hat.id }?.blocker())
    }

    func testASignInAgainMustBeTheSameOwner() throws {
        let person = CodexStoreTests.person()
        let hat = try store.addCodexHat(newHat(person), login: CodexFixture.login(person, refresh: "r"), isLive: false)
        let impostor = CodexFixture.Person(user: "user-other", account: "acct-other", email: person.email)

        XCTAssertThrowsError(try store.checkCodexRelogin(hat.id, login: CodexFixture.login(impostor, refresh: "x"))) {
            XCTAssertEqual($0 as? CodexError, .notTheSameOwner("work"))
        }
        XCTAssertEqual(try store.checkCodexRelogin(hat.id, login: CodexFixture.login(person, refresh: "y")).owner,
                       person.owner)
    }

    func testTheLiveFileDecidesWhichCodexHatIsWorn() throws {
        let person = CodexStoreTests.person()
        let hat = try store.addCodexHat(newHat(person), login: CodexFixture.login(person, refresh: "r"), isLive: false)

        store.noticeCodexLive(CodexFixture.login(person, refresh: "rotated"))
        XCTAssertEqual(store.codexActiveID, hat.id)

        store.noticeCodexLive(nil)
        XCTAssertNil(store.codexActiveID)
    }
}


private extension CodexTicket {
    var isReady: Bool? { needsSignIn ? nil : true }
}
