import XCTest
@testable import Hats

final class RenewalStepTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func expiredCredential() -> Data {
        credential(expiresAt: milliseconds(now.addingTimeInterval(-60)))
    }

    func testARenewedParkedHatGetsANumberAndTheSlotKeepsTheNewLogin() throws {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2",
                                             expiresAt: now.addingTimeInterval(28800),
                                             refreshExpiresAt: nil, scopes: [],
                                             account: "filip@example.com"))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertEqual(batch.readings["personal"]?.session?.percent, 7)
        XCTAssertNil(batch.troubles["personal"])
        XCTAssertEqual(slots.usedTokens, ["a-2"], "the number has to come from the token just minted")
        XCTAssertEqual(slots.renewals.map(\.refreshToken), ["r-1"])
        let kept = CredentialPayload(raw: try XCTUnwrap(slots.contents[slot]))
        XCTAssertEqual(kept.accessToken, "a-2")
        XCTAssertEqual(kept.oauth?.refreshToken, "r-2",
                       "a rotated refresh token that is not stored leaves the hat dead on the next poll")
        XCTAssertEqual(kept.accessExpires, now.addingTimeInterval(28800))
        XCTAssertEqual(slots.logged.map(\.operation), ["renew.done"],
                       "the renewal writes one line, and it goes through the world so a test run "
                           + "cannot append fabricated entries to the operator's real journal")
    }

    func testTheBatchCarriesTheMintSoTheStoredExpiriesCanFollowIt() throws {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2",
                                             expiresAt: now.addingTimeInterval(28800),
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        let mint = try XCTUnwrap(batch.renewals["personal"])
        XCTAssertEqual(mint.expiresAt, now.addingTimeInterval(28800),
                       "the keychain got the new login and the account record did not, so the "
                           + "horizon line kept quoting an expiry the renewal had already moved")
        XCTAssertNil(batch.renewals["absent"])
    }

    func testARenewalThatCouldNotBeStoredIsNotReportedAsAMint() {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.writeFailures = [slot]
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertTrue(batch.renewals.isEmpty,
                      "the expiry recorded on the hat has to describe what the keychain holds; a "
                          + "mint that never reached the slot would move the record ahead of it")
    }

    func testARenewedParkedHatIsNeverCountedAsARefusalAgainstTheWornOne() {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertTrue(batch.refused.isEmpty,
                      "a parked token is not the one in use, so a refusal met on the renewal path "
                          + "must not block the hat from the switch that would have renewed it")
    }

    func testAParkedHatStillRenewsWhenTheAccountFileCannotBeResolved() throws {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2",
                                             expiresAt: now.addingTimeInterval(28800),
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)],
                                            world: slots.world(now: now, liveSlot: nil))

        XCTAssertEqual(batch.readings["personal"]?.session?.percent, 7,
                       "a parked slot is named after the hat, not after the CLI configuration, so "
                           + "two account files stopping the worn hat's read must not stop a parked "
                           + "hat from renewing its own login")
        XCTAssertEqual(slots.renewals.map(\.refreshToken), ["r-1"])
        XCTAssertEqual(CredentialPayload(raw: try XCTUnwrap(slots.contents[slot])).accessToken, "a-2")
    }

    func testARenewalThatLandsOnASlotSomebodyElseRewroteIsThrownAway() {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.movesTo[slot] = credential(access: "someone-else", expiresAt: nil, refresh: "r-9")
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertEqual(batch.troubles["personal"],
                       .renewalFailed("the login moved while it was being renewed"))
        XCTAssertNil(batch.readings["personal"])
        XCTAssertEqual(slots.usedTokens, [], "spending the minted token would report the wrong hat's limits")
        XCTAssertEqual(slots.writes.count, 0,
                       "the blob a switch parked here is newer than ours, so writing over it would "
                           + "undo the switch and leave the app wearing a hat whose slot says otherwise")
    }

    func testASlotEmptiedWhileTheRenewalWasInFlightIsNotTreatedAsOurs() {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.movesTo[slot] = credential(access: "", expiresAt: nil, refresh: nil)
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertEqual(batch.troubles["personal"],
                       .renewalFailed("the login moved while it was being renewed"),
                       "the compare-and-swap was copied from the CLI, which allows an empty stored "
                           + "token because it is filling the slot it just read; ours is a parked "
                           + "slot another operation may have cleared, and splicing our mint into "
                           + "that payload revives a login the person had just cleared")
        XCTAssertEqual(slots.writes.count, 0)
    }

    func testNothingIsSpentWhenTheHatIsAlreadyWornAtTheStart() throws {
        let slot = Slot.parked("personal")
        let parked = expiredCredential()
        let slots = FakeSlots([slot: parked, FakeSlots.live: parked])
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertEqual(batch.troubles["personal"],
                       .renewalFailed("the hat is worn, so the CLI renews this login itself"),
                       "activate does not clear the parked slot, so after a switch the same blob "
                           + "sits in both slots and the compare-and-swap passes — it compares the "
                           + "parked slot with itself while the harm lands on the live one")
        XCTAssertTrue(slots.renewals.isEmpty,
                      "and the question is asked BEFORE the token is posted: a refusal that comes "
                          + "after the request has already spent the refresh token, and if the "
                          + "server rotated it in that exchange the live login the CLI uses is left "
                          + "holding one the server retired")
        XCTAssertEqual(slots.writes.count, 0)
        XCTAssertEqual(slots.usedTokens, [])
        XCTAssertEqual(CredentialPayload(raw: try XCTUnwrap(slots.contents[slot])).oauth?.refreshToken,
                       "r-1")
    }

    func testAHatWornWhileTheRequestWasInFlightStillDiscardsTheMint() {
        let slot = Slot.parked("personal")
        let parked = expiredCredential()
        let slots = FakeSlots([slot: parked,
                               FakeSlots.live: credential(expiresAt: nil, refresh: "r-9")])
        slots.movesTo[FakeSlots.live] = parked
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertEqual(batch.troubles["personal"],
                       .renewalFailed("the hat was worn while its login was being renewed"),
                       "the live slot carried somebody else when the question was asked and this "
                           + "hat by the time the answer came back, so the check before the request "
                           + "narrows the window without closing it and the one after it stays")
        XCTAssertEqual(slots.renewals.map(\.refreshToken), ["r-1"], "this one did spend the token")
        XCTAssertEqual(slots.writes.count, 0, "and still writes nothing")
    }

    func testALifetimeTooLargeToStoreIsRefusedInsteadOfTrapping() {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2",
                                             expiresAt: Date(timeIntervalSince1970: 1e30),
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertEqual(batch.troubles["personal"],
                       .renewalFailed("the credential could not be rewritten"),
                       "expires_in of 1e30 reached a trapping Int(Double) conversion and took the "
                           + "whole menu-bar app down from the poll queue — and the app is what "
                           + "holds the parked hats. The bound is not a chosen threshold: the value "
                           + "has to be representable as milliseconds since the epoch in an Int")
        XCTAssertEqual(slots.writes.count, 0)
    }

    func testAMintIsDiscardedWhenTheWornLoginCannotBeReadAtAll() {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential(), FakeSlots.live: expiredCredential()])
        slots.readFailures = [FakeSlots.live]
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertEqual(batch.troubles["personal"],
                       .renewalFailed("the worn login could not be checked"),
                       "a check that cannot be made is not a check that passed; the cure for a "
                           + "locked keychain is a skipped renewal, and the cure for guessing is a "
                           + "logged-out account")
        XCTAssertEqual(slots.writes.count, 0)
    }

    func testAMintGoesAheadWhenTheWornLoginIsADifferentOne() throws {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential(),
                               FakeSlots.live: credential(expiresAt: nil, refresh: "r-9")])
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertNil(batch.troubles["personal"],
                     "the ordinary case is a worn hat that is somebody else, and the guard must not "
                         + "stop every renewal just because a live slot exists")
        XCTAssertEqual(CredentialPayload(raw: try XCTUnwrap(slots.contents[slot])).accessToken, "a-2")
    }

    func testTheLiveSlotStandingTellsThreeAnswersApart() {
        let unresolvable = FakeSlots([:])
        XCTAssertEqual(
            AutoSwitchWatch.standingOfTheLiveSlot("r-1",
                                                  world: unresolvable.world(now: now, liveSlot: nil)),
            .doesNotCarryIt,
            "a parked slot is named after the hat, so an unresolvable account file cannot mean the "
                + "hat was worn — activate reads that configuration too and throws before it writes")

        let empty = FakeSlots([:])
        XCTAssertEqual(AutoSwitchWatch.standingOfTheLiveSlot("r-1", world: empty.world(now: now)),
                       .doesNotCarryIt)

        let promoted = FakeSlots([FakeSlots.live: expiredCredential()])
        XCTAssertEqual(AutoSwitchWatch.standingOfTheLiveSlot("r-1", world: promoted.world(now: now)),
                       .carriesIt)

        let locked = FakeSlots([FakeSlots.live: expiredCredential()])
        locked.readFailures = [FakeSlots.live]
        XCTAssertEqual(AutoSwitchWatch.standingOfTheLiveSlot("r-1", world: locked.world(now: now)),
                       .cannotBeRead)
    }

    func testAMintThatCannotBeStoredIsReportedRatherThanQuietlyUsed() {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.writeFailures = [slot]
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertEqual(batch.troubles["personal"],
                       .renewalFailed("the renewed login could not be stored"))
        XCTAssertNil(batch.readings["personal"],
                     "a number drawn from a token nothing kept leaves a working display over a hat "
                         + "whose stored refresh token the server may have just rotated away")
        XCTAssertEqual(slots.writes.map(\.service), [slot], "the write was attempted, and it threw")
    }

    func testAWriteThatDoesNotThrowButDoesNotTakeIsCaught() {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.swallowsWrites = true
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertEqual(batch.troubles["personal"],
                       .renewalFailed("the renewed login did not reach the keychain"),
                       "AccountStore writes every credential through writeVerified, which reads the "
                           + "slot back and throws writeDidNotTake; a write that silently does not "
                           + "take would leave the old refresh token in the slot after the server "
                           + "may have rotated it away")
        XCTAssertNil(batch.readings["personal"],
                     "and the minted token must not be spent on a reading either")
    }

    func testAWriteThatLandedButCannotBeReadBackIsNotCalledARefusedWrite() {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.failReadsAfter = 2
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now))

        XCTAssertEqual(batch.troubles["personal"],
                       .renewalFailed("the renewed login could not be read back"),
                       "a keychain that refused the write and a keychain that took it but cannot be "
                           + "read are opposite cures, and one do/catch around both reported the "
                           + "second as the first")
        XCTAssertEqual(slots.writes.map(\.service), [slot], "the write itself did happen")
    }

    func testARefusedGrantAsksForALoginAndATransientFailureDoesNot() {
        let slot = Slot.parked("personal")

        let refused = FakeSlots([slot: expiredCredential()])
        refused.answer = .needsLogin
        XCTAssertEqual(AutoSwitchWatch.fetched([("personal", false)], world: refused.world(now: now))
            .troubles["personal"], .parkedNeedsLogin)

        let blip = FakeSlots([slot: expiredCredential()])
        blip.answer = .failed("unreachable")
        XCTAssertEqual(AutoSwitchWatch.fetched([("personal", false)], world: blip.world(now: now))
            .troubles["personal"], .renewalFailed("unreachable"))
    }

    func testAHatHeldBackByTheBackoffSpendsNothingAndSaysNothingNew() {
        let slot = Slot.parked("personal")
        let slots = FakeSlots([slot: expiredCredential()])
        slots.answer = .renewed(RenewedLogin(accessToken: "a-2", refreshToken: "r-2", expiresAt: now,
                                             refreshExpiresAt: nil, scopes: [], account: nil))
        var world = slots.world(now: now)
        world.mayRenew = { _ in false }

        let batch = AutoSwitchWatch.fetched([("personal", false)], world: world)

        XCTAssertTrue(slots.renewals.isEmpty, "the whole point is not to ask the token endpoint again")
        XCTAssertTrue(slots.writes.isEmpty)
        XCTAssertNil(batch.troubles["personal"],
                     "and it records no trouble at all: landed keeps the previous one for a hat "
                         + "that got no fresh reading, so the row stays exactly as it was and "
                         + "usage.trouble writes nothing, because nothing changed")
        XCTAssertNil(batch.readings["personal"])
    }
}
