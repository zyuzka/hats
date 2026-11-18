import XCTest
@testable import Hats

final class ClaudeDoorsTests: ClaudeCodexPairCase {
    func testTheLiveClaudeLoginIsMatchedToTheClaudeHat() throws {
        try bothOrders { pair, order in
            let outcome = try pair.store.reconcileWithLiveLogin(observing: .account(pair.address), claiming: .noWatch)

            XCTAssertEqual(outcome, .reconciled(account: pair.address, changed: true), order)
            XCTAssertEqual(pair.store.activeID, pair.claude.id, order)
            XCTAssertEqual(pair.keychain.contents[Slot.parked(pair.claude.id)], liveLogin, order)
            XCTAssertNil(pair.keychain.contents[Slot.parked(pair.codex.id)], order)
        }
    }

    func testTheLoginParkedBeforeASignInGoesToTheClaudeHat() throws {
        try bothOrders { pair, order in
            let target = try pair.store.add(email: "target-\(UUID().uuidString.prefix(8))@b.com", browser: nil)

            try pair.store.parkTheLiveLoginBeforeSigningIn(target)

            XCTAssertEqual(pair.keychain.contents[Slot.parked(pair.claude.id)], liveLogin, order)
            XCTAssertNil(pair.keychain.contents[Slot.parked(pair.codex.id)], order)
        }
    }

    func testAClaudeDuplicateIsOnlyAClaudeHat() throws {
        try bothOrders { pair, order in
            XCTAssertThrowsError(try pair.store.add(email: pair.address, browser: nil), order)
        }
    }

    func testOnlyClaudeHatsArePolledAndOnlyByTheClaudeLogin() throws {
        try bothOrders { pair, order in
            let polled = ClaudeDoors.hatsForUsage(pair.store.accounts, live: pair.address)

            XCTAssertFalse(polled.contains { $0.id == pair.codex.id }, order)
            XCTAssertEqual(polled.first { $0.id == pair.claude.id }?.isWearing, true, order)
            XCTAssertFalse(pair.store.claudeHats.contains { $0.id == pair.codex.id }, order)
        }
    }

    func testTheCodexSlotSurvivesThePruneOfClaudeSlots() throws {
        try bothOrders { pair, order in
            pair.keychain.contents[Slot.parked("orphan-\(UUID().uuidString.prefix(4))")] = liveLogin

            pair.store.pruneOrphanedCredentials()

            XCTAssertNotNil(pair.keychain.contents[Slot.codexParked(pair.codex.id)], order)
            XCTAssertFalse(pair.keychain.deletes.contains(Slot.codexParked(pair.codex.id)), order)
        }
    }

    func testTheSoonestParkedExpiryIsAClaudeOne() throws {
        try bothOrders { pair, order in
            try pair.store.noteActivated(pair.claude.id, target: pair.claude)
            let soonest = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 90).rounded(.down))
            let owner = try XCTUnwrap(pair.codex.codexOwner)
            let person = CodexFixture.Person(user: owner.userID, account: owner.accountID, email: pair.address)
            pair.store.noteCodexLogin(pair.codex.id, login: CodexFixture.login(person, refresh: "soon", expiresAt: soonest),
                                      signedIn: false)
            let codexExpiry = pair.store.accounts.first { $0.id == pair.codex.id }?.accessExpiresAt
            XCTAssertEqual(codexExpiry, soonest, "earlier than any Claude hat of the suite")

            XCTAssertNotNil(codexExpiry)
            XCTAssertNotEqual(pair.store.soonestParkedAccessExpiry, codexExpiry, order)
        }
    }
}
