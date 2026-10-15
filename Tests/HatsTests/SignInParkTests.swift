import XCTest
@testable import Hats

final class SignInParkTests: XCTestCase {
    private var home = URL(fileURLWithPath: "/")

    private let wornEmail = "signin-worn-\(UUID().uuidString.prefix(8))@b.com"
    private let targetEmail = "signin-target-\(UUID().uuidString.prefix(8))@b.com"
    private let liveLogin = credential(access: "live-new", expiresAt: 1_800_000_000_000)
    private let staleCopy = credential(access: "parked-old", expiresAt: 1_700_000_000_000)

    override func setUpWithError() throws {
        let override = ProcessInfo.processInfo.environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(override.isEmpty,
                      "the store writes accounts.json through StateDirectory, which reads "
                          + "HATS_STATE_HOME from the process environment")
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("hats-signin-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try JSONSerialization
            .data(withJSONObject: [
                "oauthAccount": ["emailAddress": wornEmail],
                "userID": "user-worn",
            ])
            .write(to: home.appendingPathComponent(".claude.json"))
    }

    override func tearDownWithError() throws {
        CLIState.forgetTheCLIConfiguration()
        try? FileManager.default.removeItem(at: home)
    }

    private func world(status: CLI.Status?, live: Data?) -> (AccountStore, FakeKeychain, String) {
        let liveSlot = CLIState.credentialService(environment: [:])
        var contents: [String: Data] = [:]
        if let live { contents[liveSlot] = live }
        let keychain = FakeKeychain(contents)
        let system = FakeSystem(home: home.path)
        system.status = status
        let store = AccountStore(osAccount: "signin-park-test",
                                 keychain: keychain.world(),
                                 system: system.world())
        store.fetchingTokenIdentity = { _ in .unreachable }

        return (store, keychain, liveSlot)
    }

    func testSigningIntoAnotherHatParksTheLoginThatIsAboutToBeOverwritten() throws {
        let (store, keychain, liveSlot) = world(status: loggedIn(as: wornEmail), live: liveLogin)
        let worn = try store.add(email: wornEmail, browser: nil)
        let target = try store.add(email: targetEmail, browser: nil)
        keychain.contents[Slot.parked(worn.id)] = staleCopy

        try store.parkTheLiveLoginBeforeSigningIn(target)

        XCTAssertEqual(keychain.contents[Slot.parked(worn.id)], liveLogin,
                       "Claude Code had replaced the worn hat's login since it was parked, and "
                           + "the sign-in overwrites the live slot. Without this the hat kept the "
                           + "old copy and the server refused it one second later — measured "
                           + "twice on 2026-10-14, 10:47:23 and 10:49:29")
        XCTAssertEqual(keychain.contents[liveSlot], liveLogin, "the live slot is left alone")
        XCTAssertNil(keychain.contents[Slot.parked(target.id)])
    }

    func testSigningIntoTheWornHatAgainParksNothing() throws {
        let (store, keychain, _) = world(status: loggedIn(as: wornEmail), live: liveLogin)
        let worn = try store.add(email: wornEmail, browser: nil)
        keychain.contents[Slot.parked(worn.id)] = staleCopy

        try store.parkTheLiveLoginBeforeSigningIn(worn)

        XCTAssertTrue(keychain.writes.isEmpty, "the new login replaces this one through capture")
    }

    func testAnEmptyLiveSlotParksNothing() throws {
        let (store, keychain, _) = world(status: nil, live: nil)
        let target = try store.add(email: targetEmail, browser: nil)

        try store.parkTheLiveLoginBeforeSigningIn(target)

        XCTAssertTrue(keychain.writes.isEmpty)
    }

    func testALiveLoginWhoseOwnerCannotBeReadRefusesTheSignIn() throws {
        let (store, keychain, liveSlot) = world(status: nil, live: liveLogin)
        let worn = try store.add(email: wornEmail, browser: nil)
        let target = try store.add(email: targetEmail, browser: nil)
        keychain.contents[Slot.parked(worn.id)] = staleCopy

        XCTAssertThrowsError(try store.parkTheLiveLoginBeforeSigningIn(target),
                             "the live login may be a hat's newest copy, and a sign-in would overwrite "
                                 + "it with nothing kept — a switch refuses on the same reading") { error in
            guard case .identityUnknown = error as? SwitchError else {
                return XCTFail("refused for the wrong reason: \(error)")
            }
        }
        XCTAssertTrue(keychain.writes.isEmpty)
        XCTAssertEqual(keychain.contents[liveSlot], liveLogin)
    }

    func testALiveSlotTheCLICallsLoggedOutParksNothingAndLetsTheSignInGo() throws {
        let loggedOut = CLI.Status(loggedIn: false, email: nil, orgName: nil, subscriptionType: nil, authMethod: nil)
        let (store, keychain, _) = world(status: loggedOut, live: liveLogin)
        let target = try store.add(email: targetEmail, browser: nil)

        XCTAssertNoThrow(try store.parkTheLiveLoginBeforeSigningIn(target),
                         "Claude Code itself says nobody is logged in, so the slot holds no login to keep")
        XCTAssertTrue(keychain.writes.isEmpty)
    }

    func testAParkThatCannotBeWrittenStopsTheSignInAndLeavesTheOldCopy() throws {
        let (store, keychain, _) = world(status: loggedIn(as: wornEmail), live: liveLogin)
        let worn = try store.add(email: wornEmail, browser: nil)
        let target = try store.add(email: targetEmail, browser: nil)
        keychain.contents[Slot.parked(worn.id)] = staleCopy
        keychain.writeFailures = [Slot.parked(worn.id)]

        XCTAssertThrowsError(try store.parkTheLiveLoginBeforeSigningIn(target),
                             "going ahead would overwrite the only copy of the newest login; the person "
                                 + "sees the keychain error and can retry")
        XCTAssertEqual(keychain.contents[Slot.parked(worn.id)], staleCopy)
    }

    func testALiveLoginThatIsNoHatIsLeftWhereItIs() throws {
        let (store, keychain, _) = world(status: loggedIn(as: "stranger@b.com"), live: liveLogin)
        let target = try store.add(email: targetEmail, browser: nil)

        XCTAssertNoThrow(try store.parkTheLiveLoginBeforeSigningIn(target),
                         "a login nobody added as a hat has no slot to go to, and refusing the "
                             + "sign-in over it would lock the person out of adding one")
        XCTAssertTrue(keychain.writes.isEmpty)
    }

    func testStartingASignInParksTheLiveLoginFirst() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Hats/AccountStore.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "func beginLogin(")).upperBound
        let rest = source[start...]
        let body = rest[..<(try XCTUnwrap(rest.range(of: "\n    }")).upperBound)]

        XCTAssertTrue(body.contains("parkTheLiveLoginBeforeSigningIn"),
                      "beginLogin needs the claude executable, which CI does not have, so the call "
                          + "is held here in the source and the behaviour in the tests above")
    }
}
