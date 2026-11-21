import XCTest
@testable import Hats

class ClaudeCodexPairCase: XCTestCase {
    var home = URL(fileURLWithPath: "/")
    let liveLogin = credential(access: "claude-live", expiresAt: 1_800_000_000_000)

    override func setUpWithError() throws {
        let override = ProcessInfo.processInfo.environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(override.isEmpty, "the store writes accounts.json through StateDirectory")
        home = FileManager.default.temporaryDirectory.appendingPathComponent("hats-doors-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        CLIState.forgetTheCLIConfiguration()
        try? FileManager.default.removeItem(at: home)
    }

    struct Pair {
        let store: AccountStore
        let keychain: FakeKeychain
        let claude: Account
        let codex: Account
        let liveSlot: String
        let address: String
    }

    func pair(codexFirst: Bool) throws -> Pair {
        let address = "door-\(UUID().uuidString.prefix(8))@example.com"
        CLIState.forgetTheCLIConfiguration()
        try JSONSerialization.data(withJSONObject: ["oauthAccount": ["emailAddress": address], "userID": "user-door"])
            .write(to: home.appendingPathComponent(".claude.json"))
        let liveSlot = CLIState.credentialService(environment: [:])
        let keychain = FakeKeychain([liveSlot: liveLogin])
        let system = FakeSystem(home: home.path)
        system.status = loggedIn(as: address)
        let store = AccountStore(
            osAccount: "doors-test",
            keychain: keychain.world(),
            system: system.world(),
            fetchingTokenIdentity: OfflineProfile.fetch
        )
        let tag = UUID().uuidString.prefix(8).lowercased()
        let person = CodexFixture.Person(user: "user-\(tag)", account: "acct-\(tag)", email: address)
        let addCodex = {
            try store.addCodexHat(CodexNewHat(name: nil, email: address, browser: .safari),
                                  login: CodexFixture.login(person, refresh: "codex"), isLive: false)
        }
        var codex = codexFirst ? try addCodex() : nil
        let claude = try store.add(email: address, browser: nil)
        if codex == nil { codex = try addCodex() }

        return Pair(store: store, keychain: keychain, claude: claude, codex: try XCTUnwrap(codex), liveSlot: liveSlot,
                    address: address)
    }

    func bothOrders(_ check: (Pair, String) throws -> Void) throws {
        for codexFirst in [true, false] {
            try check(try pair(codexFirst: codexFirst), codexFirst ? "Codex first" : "Claude first")
        }
    }
}
