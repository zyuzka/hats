import XCTest
@testable import Hats

final class LegacySlotAdoptionTests: XCTestCase {
    private let id = "adopt-\(UUID().uuidString.prefix(8))"
    private let old = credential(access: "legacy", expiresAt: 1_700_000_000_000)
    private let new = credential(access: "current", expiresAt: 1_800_000_000_000)

    func testAHatWithOnlyTheOldSlotIsMovedUnderTheNewName() {
        let keychain = FakeKeychain([Slot.legacyParked(id): old])

        keychain.world().adoptLegacyParked(id: id)

        XCTAssertEqual(keychain.contents[Slot.parked(id)], old)
        XCTAssertNil(keychain.contents[Slot.legacyParked(id)], "the old slot goes once the new one holds it")
    }

    func testAHatThatAlreadyHasTheNewSlotKeepsItAndLosesTheOldOne() {
        let keychain = FakeKeychain([Slot.legacyParked(id): old, Slot.parked(id): new])

        keychain.world().adoptLegacyParked(id: id)

        XCTAssertEqual(keychain.contents[Slot.parked(id)], new, "the newer login is never overwritten by the old one")
        XCTAssertNil(keychain.contents[Slot.legacyParked(id)])
        XCTAssertTrue(keychain.writes.isEmpty)
    }

    func testANewSlotThatCannotBeReadIsNotTakenForAnEmptyOne() {
        let keychain = FakeKeychain([Slot.legacyParked(id): old, Slot.parked(id): new])
        keychain.readFailures = [Slot.parked(id)]

        keychain.world().adoptLegacyParked(id: id)

        XCTAssertTrue(keychain.writes.isEmpty,
                      "a read error said nothing about the slot; writing the old login there would put "
                          + "a dead credential over the one that works")
        XCTAssertEqual(keychain.contents[Slot.parked(id)], new)
        XCTAssertEqual(keychain.contents[Slot.legacyParked(id)], old, "and the old slot waits for the next launch")
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
        let store = AccountStore(osAccount: "delete-verified-test", keychain: keychain.world())

        try store.deleteVerified(slot, label: "a hat")

        XCTAssertNil(keychain.contents[slot])
        XCTAssertEqual(keychain.reads.last, slot, "the slot is read after the delete")
    }

    func testADeletionThatDidNotTakeIsCaught() {
        let slot = Slot.parked(id)
        let keychain = FakeKeychain([slot: old])
        keychain.swallowsDeletes = true
        let store = AccountStore(osAccount: "delete-verified-test", keychain: keychain.world())

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
        let store = AccountStore(osAccount: "delete-verified-test", keychain: keychain.world())

        XCTAssertThrowsError(try store.deleteVerified(slot, label: "a hat")) {
            XCTAssertTrue($0 is KeychainError, "got \($0)")
        }
        XCTAssertEqual(keychain.contents[slot], old)
    }

    func testEveryStoreBuiltByATestIsGivenAFakeKeychain() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let ownName = URL(fileURLWithPath: #filePath).lastPathComponent
        let files = try FileManager.default.contentsOfDirectory(atPath: tests.path)
            .filter { $0.hasSuffix(".swift") && $0 != ownName }
        var found = 0
        var bare: [String] = []
        for name in files {
            let text = try String(contentsOf: tests.appendingPathComponent(name), encoding: .utf8)
            for call in Self.findConstructorCalls(in: text) {
                found += 1
                if !call.contains("keychain:") { bare.append("\(name): \(call)") }
            }
        }

        XCTAssertGreaterThan(found, 0, "the search has to see the stores the tests build")
        XCTAssertEqual(bare, [],
                       "a store built without keychain: goes to /usr/bin/security and the live keychain")
    }

    private static func findConstructorCalls(in text: String) -> [String] {
        var calls: [String] = []
        var rest = text[...]
        while let start = rest.range(of: "AccountStore(") {
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
