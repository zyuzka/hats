import XCTest
@testable import Hats

final class CodexStoreIsolatedTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("hats-isolated-\(UUID().uuidString.prefix(8))")
    private let keychain = FakeKeychain()
    private lazy var index = folder.appendingPathComponent("accounts.json")
    private lazy var store = AccountStore(
        osAccount: "isolated",
        keychain: keychain.world(),
        index: index,
        fetchingTokenIdentity: OfflineProfile.fetch
    )

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func codex(_ person: CodexFixture.Person, refresh: String = "r",
                       expiresAt: Date = CodexFixture.now.addingTimeInterval(5 * 86_400)) throws -> Account {
        try store.addCodexHat(CodexNewHat(name: nil, email: person.email, browser: .safari),
                              login: CodexFixture.login(person, refresh: refresh, expiresAt: expiresAt),
                              isLive: false)
    }

    func testTwoWorkspacesOfOneAddressAreTwoHatsAndOneOwnerIsOne() throws {
        let first = CodexFixture.Person(user: "u-1", account: "acct-plus", email: "work@example.com")
        let second = CodexFixture.Person(user: "u-1", account: "acct-business", email: "work@example.com")

        _ = try codex(first)
        _ = try codex(second)

        XCTAssertEqual(store.codexHats.count, 2)
        XCTAssertThrowsError(try codex(second, refresh: "again")) {
            XCTAssertEqual($0 as? CodexError, .duplicateOwner("work@example.com"))
        }
    }

    func testTheLastHatIsCountedPerProvider() throws {
        let claudeA = try store.add(email: "a@example.com", browser: nil)
        _ = try store.add(email: "b@example.com", browser: nil)
        let only = try codex(CodexFixture.work)

        XCTAssertThrowsError(try store.remove(only.id)) {
            guard case .cannotRemoveLast = $0 as? SwitchError else { return XCTFail("\($0)") }
        }
        XCTAssertNoThrow(try store.remove(claudeA.id))
    }

    func testRemovingAClaudeHatLeavesTheCodexSlotsInBothOrders() throws {
        for codexFirst in [true, false] {
            let tag = UUID().uuidString.prefix(6).lowercased()
            let person = CodexFixture.Person(user: "u-\(tag)", account: "a-\(tag)", email: "\(tag)@example.com")
            let codexHat = codexFirst ? try codex(person) : nil
            let worn = try store.add(email: "worn-\(tag)@example.com", browser: nil)
            let parked = try store.add(email: person.email, browser: nil)
            let laterCodex = try codexHat ?? codex(person)
            try store.noteActivated(worn.id, target: worn)
            keychain.contents[Slot.parked(parked.id)] = Data("p".utf8)
            keychain.contents[Slot.legacyParked(parked.id)] = Data("l".utf8)

            XCTAssertThrowsError(try store.remove(worn.id))
            try store.remove(parked.id)

            XCTAssertTrue(keychain.deletes.contains(Slot.parked(parked.id)))
            XCTAssertTrue(keychain.deletes.contains(Slot.legacyParked(parked.id)))
            XCTAssertNotNil(keychain.contents[Slot.codexParked(laterCodex.id)], "codexFirst \(codexFirst)")
            XCTAssertFalse(keychain.deletes.contains { $0.hasPrefix(Slot.codexParked("")) })
        }
    }

    func testAnUpdateOfAnUnknownHatWritesNothing() throws {
        try store.update(Account(id: "nobody", email: "n@example.com"))

        XCTAssertFalse(FileManager.default.fileExists(atPath: index.path))
    }

    func testWearingAnUnknownCodexHatChangesNothing() throws {
        let hat = try codex(CodexFixture.work)
        try store.noteCodexWorn(hat.id)

        try store.noteCodexWorn("nobody")

        XCTAssertEqual(store.codexActiveID, hat.id)
    }
}
