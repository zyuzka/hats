import XCTest
@testable import Hats

final class WriteVerifiedTests: XCTestCase {
    private let slot = Slot.parked("write-verified")
    private let blob = credential(expiresAt: 1_700_000_000_000)

    private func store(_ keychain: FakeKeychain) -> AccountStore {
        AccountStore(osAccount: "write-verified-test", keychain: keychain.world())
    }

    func testAWriteThatTookComesBackAsWhatWasWritten() throws {
        let keychain = FakeKeychain()

        let written = try store(keychain).writeVerified(blob, to: slot, label: "a hat")

        XCTAssertEqual(written, blob, "the credential is passed through byte for byte, never "
            + "rebuilt from parsed fields — the same JSON carries the MCP servers' OAuth tokens")
        XCTAssertEqual(keychain.contents[slot], blob)
        XCTAssertEqual(keychain.writes.map(\.service), [slot])
    }

    func testAWriteThatDoesNotTakeIsCaughtByReadingItBack() {
        let keychain = FakeKeychain()
        keychain.swallowsWrites = true

        XCTAssertThrowsError(try store(keychain).writeVerified(blob, to: slot, label: "a hat")) {
            guard let switchError = $0 as? SwitchError,
                  case .writeDidNotTake(let label) = switchError else {
                return XCTFail("expected writeDidNotTake, got \($0)")
            }
            XCTAssertEqual(label, "a hat",
                           "a keychain that accepts the write and keeps the old contents leaves "
                               + "the switch reporting a credential it never stored, and the error "
                               + "has to name which slot so the person can be told which hat")
        }
        XCTAssertEqual(keychain.writes.map(\.service), [slot], "the write was attempted")
    }

    func testAWriteThatLandedButCannotBeReadBackIsNotCalledARefusedWrite() {
        let keychain = FakeKeychain()
        keychain.failReadsAfter = 0

        XCTAssertThrowsError(try store(keychain).writeVerified(blob, to: slot, label: "a hat")) {
            XCTAssertNil($0 as? SwitchError,
                         "a keychain that refused the write and one that took it but cannot be "
                             + "read back are opposite cures; reporting the second as "
                             + "writeDidNotTake would send the caller to roll back a write that "
                             + "is in the slot")
            XCTAssertTrue($0 is KeychainError, "the read's own error travels, got \($0)")
        }
        XCTAssertEqual(keychain.contents[slot], blob, "the write itself did land")
    }

    func testAStoreBuiltWithoutASubstitutionKeepsTheRealKeychain() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats")
        let store = try String(contentsOf: sources.appendingPathComponent("AccountStore.swift"),
                               encoding: .utf8)
        let seam = try String(contentsOf: sources.appendingPathComponent("KeychainWorld.swift"),
                              encoding: .utf8)

        XCTAssertTrue(store.contains("self.keychain = keychain ?? .real(osAccount: osAccount)"),
                      "the seam's default is the real keychain, so production behaviour is "
                          + "unchanged by the seam existing. Asserted on the text rather than by "
                          + "calling it, because a call would run /usr/bin/security against the "
                          + "developer's own login keychain — which the suite must never do")
        for call in ["Keychain.read(service: $0, account: osAccount)",
                     "Keychain.write(service: $0, account: osAccount, data: $1)",
                     "Keychain.delete(service: $0, account: osAccount)",
                     "Keychain.parkedAccountIDs(account: osAccount)"] {
            XCTAssertTrue(seam.contains(call), "the real world still calls \(call)")
        }
    }
}
