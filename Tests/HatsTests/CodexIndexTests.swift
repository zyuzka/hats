import XCTest
@testable import Hats

final class CodexIndexTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("hats-index-\(UUID().uuidString.prefix(8))")

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ keychain: FakeKeychain) -> AccountsFile {
        AccountsFile(keychain: keychain.world(), location: folder.appendingPathComponent("accounts.json"))
    }

    func testAnIndexLostWithOnlyACodexSlotLeftIsNotAFirstStart() {
        let keychain = FakeKeychain([Slot.codexParked("codex-hat"): Data("{}".utf8)])

        guard case .unusable(let reason) = file(keychain).load() else { return XCTFail("a first start was assumed") }
        guard case .indexLost = reason else { return XCTFail("\(reason)") }
    }

    func testAnIndexLostIsSeenFromTheSlotsOfEitherProvider() {
        let both = FakeKeychain([Slot.parked("claude-hat"): Data("{}".utf8), Slot.codexParked("codex-hat"): Data("{}".utf8)])
        let claudeOnly = FakeKeychain([Slot.parked("claude-hat"): Data("{}".utf8)])
        let codexOnly = FakeKeychain([Slot.codexParked("codex-hat"): Data("{}".utf8)])

        for (keychain, what) in [(both, "both"), (claudeOnly, "Claude only"), (codexOnly, "Codex only")] {
            guard case .unusable(.indexLost) = file(keychain).load() else { return XCTFail(what) }
        }
    }

    func testNoSlotsAtAllIsAFirstStart() {
        guard case .nothingYet = file(FakeKeychain()).load() else { return XCTFail("expected nothing yet") }
    }

    func testAnIndexWrittenBeforeCodexReadsAsClaudeHats() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"accounts":[{"id":"a","email":"a@b.co","hasStoredCredentials":true},{"id":"b","email":"b@b.co","hasStoredCredentials":false}],"activeID":"a"}"#.utf8)
            .write(to: folder.appendingPathComponent("accounts.json"))

        guard case .contents(let contents) = file(FakeKeychain()).load() else { return XCTFail("unreadable") }

        XCTAssertEqual(contents.accounts.map(\.wornTool), [.claudeCode, .claudeCode])
        XCTAssertTrue(contents.accounts.allSatisfy(\.isClaude))
        XCTAssertEqual(contents.activeID, "a")
        XCTAssertNil(contents.codexActiveID)
    }

    func testTheWornHatOfEachProviderIsKeptApart() throws {
        let saving = file(FakeKeychain())
        var codex = Account(id: "c", email: "a@b.co")
        codex.tool = .codex
        try saving.save(.init(accounts: [Account(id: "a", email: "a@b.co"), codex], activeID: "a", codexActiveID: "c"))

        guard case .contents(let contents) = saving.load() else { return XCTFail("unreadable") }

        XCTAssertEqual(contents.activeID, "a")
        XCTAssertEqual(contents.codexActiveID, "c")
        XCTAssertEqual(contents.accounts.map(\.wornTool), [.claudeCode, .codex])
    }

    private func source(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/\(name)")

        return try String(contentsOf: url, encoding: .utf8)
    }

    func testAClickOnACodexHatLeavesBeforeTheClaudeStateIsTouched() throws {
        let actions = try source("AppDelegate+Actions.swift")
        let codex = try source("AppDelegate+Codex.swift")
        let routed = try XCTUnwrap(actions.range(of: "== .codex { return wearCodex(id) }")).lowerBound
        let takenAway = try XCTUnwrap(actions.range(of: "let takenAway = whatTheWearTakesAway()")).lowerBound

        XCTAssertLessThan(routed, takenAway, "a Codex hat leaves before the Claude warning is taken away")
        XCTAssertFalse(codex.contains("autoSwitchRecord"))
        XCTAssertFalse(codex.contains("whatTheWearTakesAway"))
        XCTAssertFalse(codex.contains("lastAutoSwitchWarning"))
    }

    func testTheClaudeListAndThePollReadOnlyClaudeHats() throws {
        XCTAssertTrue(try source("AppDelegate+Redraw.swift")
            .contains("snapshot.rows = ClaudeDoors.claudeRows(store.accounts, live: liveIdentity.email) { hat, isWearing in"))
        XCTAssertTrue(try source("main.swift").contains("ClaudeDoors.hatsForUsage(store.accounts, live: liveIdentity.email)"))
    }
}
