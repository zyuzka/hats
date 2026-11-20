import XCTest
@testable import Hats

final class CodexStoreTests: XCTestCase {
    private let keychain = FakeKeychain()
    private var store: AccountStore!

    override func setUpWithError() throws {
        let override = ProcessInfo.processInfo.environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(override.isEmpty, "the store writes accounts.json through StateDirectory")
        store = AccountStore(osAccount: "codex-store-test", keychain: keychain.world())
    }

    static func person(_ role: String = "work") -> CodexFixture.Person {
        let tag = UUID().uuidString.prefix(8).lowercased()
        return CodexFixture.Person(user: "user-\(tag)", account: "acct-\(tag)", email: "\(role)-\(tag)@example.com")
    }

    private func newHat(_ person: CodexFixture.Person, name: String? = "work") -> CodexNewHat {
        CodexNewHat(name: name, email: person.email, browser: .safari)
    }

    func testASignedInHatIsStoredInItsSlotFirstAndThenSaved() throws {
        let person = Self.person()
        let login = CodexFixture.login(person, refresh: "r-1")

        let hat = try store.addCodexHat(newHat(person), login: login, isLive: false)

        XCTAssertEqual(keychain.writes.map(\.service), [Slot.codexParked(hat.id)])
        XCTAssertEqual(keychain.contents[Slot.codexParked(hat.id)], login)
        XCTAssertFalse(Slot.codexParked(hat.id).hasPrefix(Slot.parked("")), "the prune of Claude slots never sees it")
        let saved = try XCTUnwrap(AccountStore(osAccount: "t", keychain: keychain.world()).accounts.first { $0.id == hat.id })
        XCTAssertEqual(saved.wornTool, .codex)
        XCTAssertEqual(saved.codexOwner, person.owner)
        XCTAssertEqual(saved.codexPlan, "plus")
        XCTAssertEqual(saved.browser, .safari)
        XCTAssertTrue(saved.isSwitchable, "a Codex hat needs its tokens and its owner, not a CLI identity")
        XCTAssertNotEqual(store.codexActiveID, hat.id, "a sign-in does not put the hat on")
    }

    func testTheWrongAccountLeavesNoHatAndNoSlot() throws {
        let person = Self.person()
        let other = Self.person("personal")

        XCTAssertThrowsError(try store.addCodexHat(newHat(person), login: CodexFixture.login(other, refresh: "r"),
                                                   isLive: false)) {
            XCTAssertEqual($0 as? CodexError, .wrongAccount(expected: person.email, actual: other.email))
        }
        XCTAssertTrue(keychain.writes.isEmpty)
        XCTAssertFalse(store.codexHats.contains { Account.sameAddress($0.email, person.email) })
    }

    func testALoginWithoutAnOwnerOrNotChatGPTIsRefused() {
        let person = Self.person()
        let ownerless = try? CodexAuth.signedIn(
            idToken: CodexFixture.idToken(user: person.user, account: nil, email: person.email),
            accessToken: "a",
            refreshToken: "r",
            loginOwnerID: "o",
            at: CodexFixture.now
        ).data()

        XCTAssertThrowsError(try store.addCodexHat(newHat(person), login: ownerless ?? Data(), isLive: false)) {
            XCTAssertEqual($0 as? CodexError, .noOwner)
        }
        XCTAssertThrowsError(try store.addCodexHat(newHat(person), login: Data(#"{"auth_mode":"apikey"}"#.utf8),
                                                   isLive: false)) {
            XCTAssertEqual($0 as? CodexError, .notChatGPT)
        }
        XCTAssertTrue(keychain.writes.isEmpty)
    }

    func testASlotThatDidNotTakeLeavesNoHat() {
        let person = Self.person()
        keychain.swallowsWrites = true

        XCTAssertThrowsError(try store.addCodexHat(newHat(person), login: CodexFixture.login(person, refresh: "r"),
                                                   isLive: false))
        XCTAssertFalse(store.codexHats.contains { Account.sameAddress($0.email, person.email) })
    }

    func testAClaudeHatWithTheSameAddressDoesNotStopACodexHatAndIsUntouched() throws {
        let person = Self.person()
        let claude = try store.add(email: person.email, browser: nil)

        let codex = try store.addCodexHat(newHat(person), login: CodexFixture.login(person, refresh: "r"), isLive: true)

        XCTAssertNotEqual(claude.id, codex.id)
        XCTAssertEqual(store.accounts.first { $0.id == claude.id }?.wornTool, .claudeCode)
        XCTAssertNil(keychain.contents[Slot.parked(claude.id)])
        XCTAssertEqual(store.codexActiveID, codex.id)
        XCTAssertNotEqual(store.activeID, codex.id, "the worn Claude hat is a field of its own")
    }

    func testTheSameCodexAccountTwiceIsRefused() throws {
        let person = Self.person()
        _ = try store.addCodexHat(newHat(person), login: CodexFixture.login(person, refresh: "r"), isLive: false)

        XCTAssertThrowsError(try store.addCodexHat(newHat(person), login: CodexFixture.login(person, refresh: "r2"),
                                                   isLive: false))
    }

    func testTheWornCodexHatCannotBeRemovedAndAParkedOneTakesItsSlotAlong() throws {
        let worn = Self.person()
        let parked = Self.person("personal")
        let wornHat = try store.addCodexHat(newHat(worn), login: CodexFixture.login(worn, refresh: "w"), isLive: true)
        let parkedHat = try store.addCodexHat(newHat(parked), login: CodexFixture.login(parked, refresh: "p"),
                                              isLive: false)

        XCTAssertThrowsError(try store.remove(wornHat.id))
        try store.remove(parkedHat.id)

        XCTAssertNil(keychain.contents[Slot.codexParked(parkedHat.id)])
        XCTAssertNotNil(keychain.contents[Slot.codexParked(wornHat.id)])
    }
}
