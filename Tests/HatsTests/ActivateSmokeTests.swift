import XCTest
@testable import Hats

final class ActivateSmokeTests: XCTestCase {
    private var home = URL(fileURLWithPath: "/")
    private var stateFile = URL(fileURLWithPath: "/")

    private let outgoingEmail = "smoke-out-\(UUID().uuidString.prefix(8))@b.com"
    private let incomingEmail = "smoke-in-\(UUID().uuidString.prefix(8))@b.com"
    private let outgoing = credential(access: "out-1", expiresAt: 1_700_000_000_000)
    private let incoming = credential(access: "in-1", expiresAt: 1_800_000_000_000)

    override func setUpWithError() throws {
        let override = ProcessInfo.processInfo.environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(override.isEmpty,
                      "activate writes accounts.json through StateDirectory, which reads "
                          + "HATS_STATE_HOME from the process environment rather than through any "
                          + "seam — without it this test would rewrite the developer's own hats and "
                          + "move their active one")
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("hats-smoke-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        stateFile = home.appendingPathComponent(".claude.json")
        try JSONSerialization
            .data(withJSONObject: [
                "oauthAccount": ["emailAddress": outgoingEmail],
                "userID": "user-outgoing",
                "cachedUsageUtilization": 42,
            ])
            .write(to: stateFile)
    }

    override func tearDownWithError() throws {
        CLIState.forgetTheCLIConfiguration()
        try? FileManager.default.removeItem(at: home)
    }

    private func identity(of email: String, userID: String) -> CLIIdentity {
        CLIIdentity(oauthAccount: ["emailAddress": .string(email)], userID: userID)
    }

    private func readBack() throws -> [String: Any] {
        let data = try Data(contentsOf: stateFile)

        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheWholeSwitchRunsWithNoSubprocessAndNoRealKeychain() throws {
        let liveSlot = CLIState.credentialService(environment: [:])
        let keychain = FakeKeychain([liveSlot: outgoing])
        let system = FakeSystem(home: home.path)
        system.status = loggedIn(as: outgoingEmail)
        let store = AccountStore(osAccount: "activate-smoke-test",
                                 keychain: keychain.world(),
                                 system: system.world())
        store.fetchingTokenIdentity = { _ in .unreachable }

        let leaving = try store.add(email: outgoingEmail, browser: nil)
        let arriving = try store.add(email: incomingEmail, browser: nil)
        keychain.contents[Slot.parked(arriving.id)] = incoming
        store.noteStored(arriving.id,
                         payload: CredentialPayload(raw: incoming),
                         identity: identity(of: incomingEmail, userID: "user-incoming"))

        try store.activate(arriving.id, meters: .unavailable, targetMeters: .unavailable)

        XCTAssertEqual(keychain.contents[liveSlot], incoming,
                       "the live slot carries the hat that was put on")
        XCTAssertEqual(keychain.contents[Slot.parked(leaving.id)], outgoing,
                       "and the hat that came off is parked under its own id rather than lost")
        XCTAssertEqual(store.activeID, arriving.id)

        let written = try readBack()
        XCTAssertEqual((written["oauthAccount"] as? [String: Any])?["emailAddress"] as? String,
                       incomingEmail,
                       "the account file names the new owner, which is what the CLI reads")
        XCTAssertEqual(written["userID"] as? String, "user-incoming")
        XCTAssertNil(written["cachedUsageUtilization"],
                     "an account-scoped cache left behind belongs to the hat that came off")
    }

    func testTheSwitchAsksEveryOutsideSystemThroughItsSeam() throws {
        let liveSlot = CLIState.credentialService(environment: [:])
        let keychain = FakeKeychain([liveSlot: outgoing])
        let system = FakeSystem(home: home.path)
        system.status = loggedIn(as: outgoingEmail)
        system.table = { arguments in
            arguments.contains("pid=,comm=")
                ? "111 /usr/local/bin/claude\n"
                : "111 01:00 claude\n"
        }
        system.trusts = { _ in true }
        system.environmentOf = { _ in .read([:]) }
        let store = AccountStore(osAccount: "activate-smoke-seams",
                                 keychain: keychain.world(),
                                 system: system.world())
        store.fetchingTokenIdentity = { _ in .unreachable }

        let leaving = try store.add(email: outgoingEmail, browser: nil)
        let arriving = try store.add(email: incomingEmail, browser: nil)
        keychain.contents[Slot.parked(arriving.id)] = incoming
        store.noteStored(arriving.id,
                         payload: CredentialPayload(raw: incoming),
                         identity: identity(of: incomingEmail, userID: "user-incoming"))

        try store.activate(arriving.id, meters: .unavailable, targetMeters: .unavailable)

        XCTAssertEqual(system.processTables.count, 2,
                       "the process table is read twice per sweep — once for executables, once for "
                           + "commands — and both went through the seam rather than to /bin/ps")
        XCTAssertEqual(system.budgets, [ProcessTable.budget, ProcessTable.budget],
                       "at the writer's budget, which is the half CLIStateLocationTests holds in "
                           + "the source text and this one holds in the call")
        XCTAssertEqual(system.trustAsked, [111],
                       "the session's signature was checked before its environment was believed — "
                           + "wired to the real SecCodeCheckValidity this is a live-system call")
        XCTAssertEqual(system.environmentsRead, [111, 111],
                       "and its environment was read twice, once to route the session and once to "
                           + "resolve the configuration; wired for real that is sysctl against "
                           + "somebody else's process")
        XCTAssertEqual(system.keysWanted,
                       [[ShellEnvironment.baseURLName], CLIState.configKeys],
                       "each read asks for the keys its own question needs, and the seam carries "
                           + "them rather than dropping them on the floor")
        XCTAssertGreaterThan(system.statusAsked, 0,
                             "who is logged in was asked of the seam, not of a claude subprocess")
        XCTAssertEqual(keychain.writes.map(\.service), [Slot.parked(leaving.id), liveSlot],
                       "two writes, in this order: park the outgoing login, then put the incoming "
                           + "one live. Every one of them reached the double instead of "
                           + "/usr/bin/security")
        XCTAssertTrue(keychain.reads.contains(liveSlot),
                      "and the live slot was read back after being written")
    }
}
