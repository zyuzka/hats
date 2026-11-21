import XCTest
@testable import Hats

final class LegacySlotAdoptionTests: XCTestCase {
    private let id = "adopt-\(UUID().uuidString.prefix(8))"
    private let old = credential(access: "legacy", expiresAt: 1_700_000_000_000)
    private let new = credential(access: "current", expiresAt: 1_800_000_000_000)
    private var logged: [(operation: String, details: [String: String])] = []

    func testAHatWithOnlyTheOldSlotIsMovedUnderTheNewName() {
        let keychain = FakeKeychain([Slot.legacyParked(id): old])

        keychain.world().adoptLegacyParked(id: id) { self.logged.append(($0, $1)) }

        XCTAssertEqual(keychain.contents[Slot.parked(id)], old)
        XCTAssertNil(keychain.contents[Slot.legacyParked(id)], "the old slot goes once the new one holds it")
        XCTAssertTrue(logged.isEmpty, "only a skip is journalled")
    }

    func testAHatThatAlreadyHasTheNewSlotKeepsItAndLosesTheOldOne() {
        let keychain = FakeKeychain([Slot.legacyParked(id): old, Slot.parked(id): new])

        keychain.world().adoptLegacyParked(id: id) { self.logged.append(($0, $1)) }

        XCTAssertEqual(keychain.contents[Slot.parked(id)], new, "the newer login is never overwritten by the old one")
        XCTAssertNil(keychain.contents[Slot.legacyParked(id)])
        XCTAssertTrue(keychain.writes.isEmpty)
    }

    func testANewSlotThatCannotBeReadIsNotTakenForAnEmptyOne() {
        let keychain = FakeKeychain([Slot.legacyParked(id): old, Slot.parked(id): new])
        keychain.readFailures = [Slot.parked(id)]

        keychain.world().adoptLegacyParked(id: id) { self.logged.append(($0, $1)) }

        XCTAssertTrue(keychain.writes.isEmpty,
                      "a read error said nothing about the slot; writing the old login there would put "
                          + "a dead credential over the one that works")
        XCTAssertEqual(keychain.contents[Slot.parked(id)], new)
        XCTAssertEqual(keychain.contents[Slot.legacyParked(id)], old, "and the old slot waits for the next launch")
        XCTAssertEqual(logged.map(\.operation), ["hat.legacyAdoptionSkipped"], "the skip leaves a trace")
        XCTAssertEqual(logged.first?.details["id"], id)
        XCTAssertEqual(logged.first?.details["reason"]?.contains("interaction not allowed"), true)
        XCTAssertEqual(logged.first.map { Set($0.details.keys) }, ["id", "reason"], "no credential bytes reach the journal")
    }

    func testOnlyOldSlotsAndNoIndexIsALostIndex() throws {
        let override = ProcessInfo.processInfo.environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(override.isEmpty, "AccountsFile reads accounts.json through StateDirectory")
        let file = AccountsFile(keychain: FakeKeychain([Slot.legacyParked(id): old]).world())
        let aside = file.url.appendingPathExtension("aside-\(id)")
        let hadOne = FileManager.default.fileExists(atPath: file.url.path)
        if hadOne { try FileManager.default.moveItem(at: file.url, to: aside) }
        defer { if hadOne { try? FileManager.default.moveItem(at: aside, to: file.url) } }

        let loaded = file.load()

        guard case .unusable(.indexLost(let path)) = loaded else {
            return XCTFail("a keychain holding hats with no accounts.json is a lost index, got \(loaded)")
        }
        XCTAssertEqual(path, file.url.path)
    }

    func testADeletionIsReadBack() throws {
        let slot = Slot.parked(id)
        let keychain = FakeKeychain([slot: old])
        let store = AccountStore(
            osAccount: "delete-verified-test",
            keychain: keychain.world(),
            fetchingTokenIdentity: OfflineProfile.fetch
        )

        try store.deleteVerified(slot, label: "a hat")

        XCTAssertNil(keychain.contents[slot])
        XCTAssertEqual(keychain.reads.last, slot, "the slot is read after the delete")
    }

    func testADeletionThatDidNotTakeIsCaught() {
        let slot = Slot.parked(id)
        let keychain = FakeKeychain([slot: old])
        keychain.swallowsDeletes = true
        let store = AccountStore(
            osAccount: "delete-verified-test",
            keychain: keychain.world(),
            fetchingTokenIdentity: OfflineProfile.fetch
        )

        XCTAssertThrowsError(try store.deleteVerified(slot, label: "a hat")) {
            guard case .deletionDidNotTake(let label) = $0 as? SwitchError else {
                return XCTFail("expected deletionDidNotTake, got \($0)")
            }
            XCTAssertEqual(label, "a hat")
        }
    }

    func testARefusedDeletionCarriesTheKeychainError() {
        let slot = Slot.parked(id)
        let keychain = FakeKeychain([slot: old])
        keychain.deleteFailures = [slot]
        let store = AccountStore(
            osAccount: "delete-verified-test",
            keychain: keychain.world(),
            fetchingTokenIdentity: OfflineProfile.fetch
        )

        XCTAssertThrowsError(try store.deleteVerified(slot, label: "a hat")) {
            XCTAssertTrue($0 is KeychainError, "got \($0)")
        }
        XCTAssertEqual(keychain.contents[slot], old)
    }

    func testEveryStoreBuiltByATestIsGivenAFakeKeychain() throws {
        let own = URL(fileURLWithPath: #filePath)
        let tests = own.deletingLastPathComponent().deletingLastPathComponent()
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
        let files = walk.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.standardizedFileURL != own.standardizedFileURL }
        var found = 0
        var bare: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let calls = Self.findConstructorCalls(in: text)
            found += calls.count
            bare += calls
                .filter { !$0.contains("keychain:") || Self.isRealKeychain($0) }
                .map { "\(file.lastPathComponent): \($0)" }
        }

        XCTAssertGreaterThan(found, 0, "the search has to see the stores the tests build")
        XCTAssertEqual(bare, [],
                       "a store built without keychain:, or with keychain: .real(...), goes to "
                           + "/usr/bin/security and the live keychain")
    }

    func testTheScannerSkipsTheNameInsideAStringAndFindsARealCall() {
        let text = #"""
        XCTAssertFalse(main.contains("AccountStore("))
        let store = AccountStore(osAccount: "bare")
        """#

        XCTAssertEqual(
            Self.findConstructorCalls(in: text),
            [
                #"AccountStore(osAccount: "bare")"#,
            ]
        )
    }

    private static func isRealKeychain(_ call: String) -> Bool {
        call.contains("keychain: .real(") || call.contains("keychain: KeychainWorld.real(")
    }

    static func findConstructorCalls(in text: String) -> [String] {
        var calls: [String] = []
        var rest = text[...]
        while let start = rest.range(of: "AccountStore(") {
            if start.lowerBound > rest.startIndex, rest[rest.index(before: start.lowerBound)] == "\"" {
                rest = rest[start.upperBound...]
                continue
            }
            var depth = 0
            var end = start.upperBound
            for index in rest[rest.index(before: start.upperBound)...].indices {
                if rest[index] == "(" { depth += 1 }
                if rest[index] == ")" { depth -= 1 }
                end = rest.index(after: index)
                if depth == 0 { break }
            }
            calls.append(String(rest[start.lowerBound..<end]))
            rest = rest[end...]
        }

        return calls
    }
}
