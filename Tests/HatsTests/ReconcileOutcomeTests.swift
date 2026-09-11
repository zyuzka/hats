import XCTest
@testable import Hats

final class ReconcileOutcomeTests: XCTestCase {
    func testAReconciledLiveLoginIsAnObservation() {
        XCTAssertTrue(ReconcileOutcome.reconciled(account: "a@b.co", changed: true).hasObservedTheLiveLogin)
        XCTAssertTrue(ReconcileOutcome.reconciled(account: "a@b.co", changed: false).hasObservedTheLiveLogin)
    }

    func testAnIdentityThatCouldNotBeReadIsNotAnObservation() {
        XCTAssertFalse(ReconcileOutcome.identityUnreadable.hasObservedTheLiveLogin)
    }

    func testNobodyLoggedInIsNotAnObservationOfALogin() {
        XCTAssertFalse(ReconcileOutcome.nobodyLoggedIn.hasObservedTheLiveLogin)
    }

    func testASlotThatIsEmptyOrUnreadableIsNotAnObservation() {
        XCTAssertFalse(ReconcileOutcome.liveSlotEmpty.hasObservedTheLiveLogin)
        XCTAssertFalse(ReconcileOutcome.liveSlotUnreadable.hasObservedTheLiveLogin)
    }

    private func claim(_ identity: LiveIdentity, _ slot: LiveSlotNow,
                       completed: Bool, moved: Bool) -> CredentialClaim {
        CredentialClaim(observed: identity, slot: slot, completed: completed,
                        credentialMoved: moved)
    }

    func testAClaimIsOnlyMadeWhenTheWatchSawBothHalves() {
        let blob = Data("live".utf8)
        XCTAssertEqual(claim(.account("a@b.co"), .holding(blob), completed: true, moved: true),
                       .confirmedByWatch(email: "a@b.co", credential: blob))
        XCTAssertEqual(claim(.account("a@b.co"), .holding(blob), completed: false, moved: true),
                       .watchInProgress)
        XCTAssertEqual(claim(.unreadable, .holding(blob), completed: true, moved: true),
                       .watchInProgress)
        XCTAssertEqual(claim(.account("a@b.co"), .empty, completed: true, moved: true),
                       .watchInProgress)
    }

    func testAnIdentityThatArrivedBeforeTheCredentialAuthorisesNothing() {
        let stillOld = Data("the credential that has not moved yet".utf8)
        XCTAssertEqual(claim(.account("new@b.co"), .holding(stillOld),
                             completed: true, moved: false), .watchInProgress)
    }

    func testAClaimAuthorisesOnlyTheAccountAndBlobItWasMadeFor() {
        let blob = Data("live".utf8)
        let other = Data("another login".utf8)
        let claim = CredentialClaim.confirmedByWatch(email: "a@b.co", credential: blob)
        XCTAssertTrue(claim.allows(account: "A@B.co", credential: blob))
        XCTAssertFalse(claim.allows(account: "someone@else.co", credential: blob))
        XCTAssertFalse(claim.allows(account: "a@b.co", credential: other))
        XCTAssertFalse(CredentialClaim.noWatch.allows(account: "a@b.co", credential: blob))
        XCTAssertFalse(CredentialClaim.watchInProgress.allows(account: "a@b.co",
                                                             credential: blob))
    }

    func testASyncTakesTheClaimOfWhateverWatchIsRunning() {
        XCTAssertEqual(CredentialClaim.forSync(duty: LoginWatchDuty.none), .noWatch)
        XCTAssertEqual(CredentialClaim.forSync(duty: .onDuty), .watchInProgress)
        XCTAssertEqual(CredentialClaim.forSync(duty: .staleButUnclear), .watchInProgress)
        XCTAssertEqual(CredentialClaim.forSync(duty: .staleAndGone), .noWatch)
    }

    func testOnlyASyncNobodyIsWatchingToleratesAnUnclaimedMismatch() {
        XCTAssertTrue(CredentialClaim.noWatch.allowsAnUnclaimedMismatch)
        XCTAssertFalse(CredentialClaim.watchInProgress.allowsAnUnclaimedMismatch)
        XCTAssertFalse(CredentialClaim
            .confirmedByWatch(email: "a@b.co", credential: Data("live".utf8))
            .allowsAnUnclaimedMismatch)
    }

    func testDiscoveryIsForASyncNobodyIsWatching() {
        let blob = Data("live".utf8)
        XCTAssertTrue(CredentialClaim.noWatch.allowsDiscovery(of: "a@b.co", credential: blob))
        XCTAssertFalse(CredentialClaim.watchInProgress.allowsDiscovery(of: "a@b.co",
                                                                      credential: blob))
        let claim = CredentialClaim.confirmedByWatch(email: "a@b.co", credential: blob)
        XCTAssertTrue(claim.allowsDiscovery(of: "A@B.co", credential: blob))
        XCTAssertFalse(claim.allowsDiscovery(of: "someone@else.co", credential: blob))
        XCTAssertFalse(claim.allowsDiscovery(of: "a@b.co", credential: Data("other".utf8)))
    }

    func testAnEmptySlotIsNotSomethingToReconcileAgainst() {
        XCTAssertEqual(LiveSlotReading(.empty), .unsettled(.liveSlotEmpty))
        XCTAssertEqual(LiveSlotReading(.unreadable), .unsettled(.liveSlotUnreadable))
    }

    func testOnlyAReconciledOutcomeCarriesNoReasonToKeepWaiting() {
        XCTAssertNil(ReconcileOutcome.reconciled(account: "a@b.co", changed: false).unsettledReason)
        for outcome: ReconcileOutcome in [.nobodyLoggedIn, .identityUnreadable,
                                          .liveSlotEmpty, .liveSlotUnreadable,
                                          .credentialUnclaimed] {
            XCTAssertNotNil(outcome.unsettledReason)
        }
    }

    func testEachUnsettledOutcomeSaysSomethingDifferent() {
        let reasons = Set([ReconcileOutcome.nobodyLoggedIn, .identityUnreadable,
                           .liveSlotEmpty, .liveSlotUnreadable, .credentialUnclaimed]
            .compactMap(\.unsettledReason))
        XCTAssertEqual(reasons.count, 5)
    }

    func testASlotHoldingACredentialIsWhatReconcileComparesAgainst() {
        let blob = Data("live".utf8)
        XCTAssertEqual(LiveSlotReading(.holding(blob)), .credential(blob))
    }
}
