import XCTest
@testable import Hats

final class CodexAlreadySignedInTests: XCTestCase {
    private let work = CodexFixture.work

    func testOnlyACompleteLiveLoginOfTheTypedAddressCountsAsSignedIn() {
        XCTAssertTrue(AppDelegate.isAlreadySignedIn(CodexFixture.login(work, refresh: "r"), as: "WORK@example.com"))
        XCTAssertFalse(AppDelegate.isAlreadySignedIn(CodexFixture.login(work, refresh: "r"), as: "other@example.com"))
        XCTAssertFalse(AppDelegate.isAlreadySignedIn(CodexFixture.login(work, refresh: "r", expiresAt: nil),
                                                     as: work.email), "an expiry that cannot be read is not enough")
        XCTAssertFalse(AppDelegate.isAlreadySignedIn(Data(#"{"auth_mode":"apikey"}"#.utf8), as: work.email))
        let ownerless = try? CodexAuth.signedIn(
            idToken: CodexFixture.idToken(user: "u", account: nil, email: work.email),
            accessToken: CodexFixture.accessToken(expiresAt: CodexFixture.now, tag: "a"),
            refreshToken: "r",
            loginOwnerID: "o",
            at: CodexFixture.now
        ).data()
        XCTAssertFalse(AppDelegate.isAlreadySignedIn(ownerless ?? Data(), as: work.email))
    }

    func testAnExpiredLiveLoginIsNotAdopted() {
        let expired = CodexFixture.login(work, refresh: "r", expiresAt: CodexFixture.now.addingTimeInterval(-60))

        XCTAssertFalse(AppDelegate.isAlreadySignedIn(expired, as: work.email, at: CodexFixture.now))
        XCTAssertTrue(AppDelegate.isAlreadySignedIn(CodexFixture.login(work, refresh: "r"), as: work.email,
                                                    at: CodexFixture.now))
    }

    func testTheLiveLoginIsAdoptedOnlyFromAFileStore() throws {
        let home = CodexFixture.home()
        defer { try? FileManager.default.removeItem(at: home.url) }
        let live = CodexFixture.login(work, refresh: "r")
        try live.write(to: home.auth)

        XCTAssertEqual(AppDelegate.liveLoginToAdopt(in: home, as: work.email, at: CodexFixture.now), live)
        try "cli_auth_credentials_store = \"keyring\"\n".write(to: home.config, atomically: true, encoding: .utf8)
        XCTAssertNil(AppDelegate.liveLoginToAdopt(in: home, as: work.email, at: CodexFixture.now),
                     "with a keyring store the file is not the login Codex uses")
    }

    func testTheSlotOfAnAlreadySignedInHatIsTheLiveFileByteForByte() throws {
        let override = ProcessInfo.processInfo.environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(override.isEmpty, "the store writes accounts.json through StateDirectory")
        let keychain = FakeKeychain()
        let store = AccountStore(
            osAccount: "codex-live-test",
            keychain: keychain.world(),
            fetchingTokenIdentity: OfflineProfile.fetch
        )
        let person = CodexStoreTests.person()
        let pretty = CodexFixture.login(person, refresh: "live")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: pretty) as? [String: Any])
        let compact = try JSONSerialization.data(withJSONObject: root)
        XCTAssertNotEqual(compact, pretty, "a file Codex wrote looks different from what Hats would write")

        let hat = try store.addCodexHat(CodexNewHat(name: nil, email: person.email, browser: .safari),
                                        login: compact, isLive: true)

        XCTAssertEqual(keychain.contents[Slot.codexParked(hat.id)], compact)
        XCTAssertEqual(store.codexActiveID, hat.id)
    }
}
