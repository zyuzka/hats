import XCTest
@testable import Hats

final class ClaudeDoorsSnapshotTests: ClaudeCodexPairCase {
    private func own(_ pair: Pair, also extra: [String] = []) -> [Account] {
        let ids = Set([pair.claude.id, pair.codex.id] + extra)
        return pair.store.accounts.filter { ids.contains($0.id) }
    }

    private func snapshot(_ pair: Pair, also extra: [String] = []) -> HatsSnapshot {
        var snapshot = HatsSnapshot()
        snapshot.rows = ClaudeDoors.claudeRows(own(pair, also: extra), live: pair.address) { hat, isWearing in
            HatRowState(hat: hat, isWearing: isWearing, usage: nil, usageTrouble: nil)
        }
        snapshot.codexRows = ClaudeDoors.codexRows(own(pair, also: extra), worn: pair.codex.id)
        snapshot.settings.autoSwitch = AutoSwitchPolicy(isOn: true)

        return snapshot
    }

    private func makeTheClaudeHatWearable(_ pair: Pair) {
        pair.store.noteStored(
            pair.claude.id,
            payload: CredentialPayload(raw: liveLogin),
            identity: CLIIdentity(oauthAccount: ["emailAddress": .string(pair.address)], userID: "user-door")
        )
    }

    func testTheWornClaudeHatIsFoundAmongClaudeHatsOnly() throws {
        try bothOrders { pair, order in
            let shown = snapshot(pair)

            XCTAssertEqual(shown.wearing?.id, pair.claude.id, order)
            XCTAssertFalse(shown.rows.contains { $0.id == pair.codex.id }, order)
            XCTAssertTrue(shown.codexRows.contains { $0.id == pair.codex.id && $0.isWearing }, order)
            XCTAssertEqual(HatUsageRecord.create(from: shown, readAt: [:], liveSlot: nil, aliveAt: nil).worn,
                           pair.claude.id, order)
        }
    }

    func testTheSwitchHasNoCodexHatToGoTo() throws {
        try bothOrders { pair, order in
            makeTheClaudeHatWearable(pair)
            let shown = snapshot(pair)

            XCTAssertFalse(AutoSwitchEngine.eligible(in: shown.rows).contains(pair.codex.id), order)
            XCTAssertNil(shown.nextInLine, "the Codex hat is ready, yet not a Claude hat to switch to — \(order)")
            XCTAssertFalse(HatUsageRecord.create(from: shown, readAt: [:], liveSlot: nil, aliveAt: nil)
                .hasAHatToSwitchTo, order)
        }
    }

    func testAClaudeDeadEndAndTheDotCountNoCodexHat() throws {
        try bothOrders { pair, order in
            makeTheClaudeHatWearable(pair)
            pair.store.noteCodexRenewals([.needsSignIn(pair.codex.id, "refresh_token_reused")],
                                         at: Date().addingTimeInterval(60))
            let resting = try pair.store.add(email: "rest-\(UUID().uuidString.prefix(8))@b.com", browser: nil)
            try pair.store.setVacation(resting.id, on: true, at: Date())
            let shown = snapshot(pair, also: [resting.id])

            XCTAssertEqual(shown.codexRows.first { $0.id == pair.codex.id }?.isSwitchable, false, order)
            XCTAssertTrue(AutoSwitchEngine.blocked(in: shown.rows).isEmpty, order)
            XCTAssertFalse(shown.hasABlockedHatInPlay, order)
            XCTAssertTrue(shown.isEveryOtherHatOnVacation, "the Codex hat is not on vacation — \(order)")
            XCTAssertEqual(AutoSwitchEngine.findOnVacation(in: shown.rows).map(\.id), [resting.id], order)
            let dot = MarkState.decide(
                anyHatBlocked: shown.hasABlockedHatInPlay,
                gatewayEnabled: false,
                gatewayServing: false,
                wearing: shown.wearing != nil,
                percent: nil,
                autoSwitchWarnsAboutTheWornHat: false
            )
            XCTAssertEqual(dot, .wearing(percent: nil), order)
        }
    }

    func testAClickGoesByTheProviderOfTheHat() throws {
        try bothOrders { pair, order in
            XCTAssertEqual(ClaudeDoors.route(ofAClickOn: pair.codex.id, among: pair.store.accounts), .codex, order)
            XCTAssertEqual(ClaudeDoors.route(ofAClickOn: pair.claude.id, among: pair.store.accounts), .claude, order)
        }
    }

    func testTheClaudePollAndRenewalReadNoCodexSlot() throws {
        try bothOrders { pair, order in
            pair.keychain.contents[Slot.parked(pair.claude.id)] = credential(access: "c", expiresAt: 1)
            var read: [String] = []
            var renewed: [String] = []
            let world = UsageWorld(
                liveSlot: { pair.liveSlot },
                read: { read.append($0)
                    return pair.keychain.contents[$0]
                },
                write: { _, _ in },
                renew: { token, _ in
                    renewed.append(token)
                    return .failed("not here")
                },
                usage: { _ in .errored(500) },
                now: { Date() },
                log: { _, _ in }
            )

            let polled = ClaudeDoors.hatsForUsage(own(pair), live: nil)
            let batch = AutoSwitchWatch.fetched(polled, world: world)

            XCTAssertEqual(polled.map(\.id), [pair.claude.id], order)
            XCTAssertTrue(read.contains(Slot.parked(pair.claude.id)), order)
            XCTAssertFalse(read.contains { $0.contains(pair.codex.id) }, order)
            XCTAssertFalse(renewed.contains("codex"), "the Codex refresh token never reaches Claude's renewal — \(order)")
            XCTAssertNil(batch.troubles[pair.codex.id], order)
            XCTAssertNil(batch.readings[pair.codex.id], order)
        }
    }
}
