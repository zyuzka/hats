import XCTest
@testable import Hats

final class AuthRefusalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func healthyHat(id: String = "a") -> Account {
        var hat = Account(id: id, email: "x@y.z", browser: nil)
        hat.hasStoredCredentials = true
        hat.identity = CLIIdentity(oauthAccount: [:], userID: "u")
        hat.refreshExpiresAt = now.addingTimeInterval(30 * 24 * 3600)

        return hat
    }

    func testADeclaredExpiryInTheFutureDoesNotSurviveAnObservedRefusal() {
        var hat = healthyHat()
        XCTAssertNil(hat.blocker(at: now), "a hat with a future expiry and no refusal is switchable")

        hat.authRefusedAt = now.addingTimeInterval(-60)

        XCTAssertEqual(hat.blocker(at: now), .loginRefused,
                       "the API refused this token, so the date it claims to be valid until is worthless")
        XCTAssertFalse(hat.isSwitchable)
    }

    func testARefusalOlderThanTheLastLoginIsSpent() {
        var hat = healthyHat()
        hat.authRefusedAt = now.addingTimeInterval(-3600)
        hat.lastLoginAt = now.addingTimeInterval(-60)

        XCTAssertNil(hat.blocker(at: now),
                     "the refusal was answered by logging in again; only a later one counts")
    }

    func testARefusalWithNoLoginRecordedStillBlocks() {
        var hat = healthyHat()
        hat.authRefusedAt = now.addingTimeInterval(-60)
        hat.lastLoginAt = nil

        XCTAssertEqual(hat.blocker(at: now), .loginRefused)
    }

    func testAnExpiredLoginIsStillReportedAsExpiredRatherThanRefused() {
        var hat = healthyHat()
        hat.refreshExpiresAt = now.addingTimeInterval(-1)

        XCTAssertEqual(hat.blocker(at: now), .loginExpired,
                       "nothing was observed here; the date is all there is")
    }

    func testOnlyAnUnauthorizedAnswerCountsAsARefusal() {
        XCTAssertTrue(UsageFetch.refused(401).refusedAuthorization)
        XCTAssertFalse(UsageFetch.refused(403).refusedAuthorization,
                       "403 is a door closed to this resource, not a dead login")
        XCTAssertFalse(UsageFetch.errored(500).refusedAuthorization)
        XCTAssertFalse(UsageFetch.unreachable.refusedAuthorization,
                       "no answer is not an answer of no")
    }

    func testTheRefusalReachesTheBatchTheWatchHandsUp() {
        var batch = AutoSwitchWatch.Batch()
        AutoSwitchWatch.record(.refused(401), for: "dead", in: &batch)
        AutoSwitchWatch.record(.refused(403), for: "forbidden", in: &batch)
        AutoSwitchWatch.record(.unreachable, for: "offline", in: &batch)

        XCTAssertEqual(batch.refused, ["dead"])
        XCTAssertEqual(batch.troubles.keys.sorted(), ["dead", "forbidden", "offline"],
                       "every one of them is still a trouble on the row")
    }

    private func row(_ hat: Account) -> HatRowState {
        HatRowState(hat: hat, isWearing: false, usage: nil, usageTrouble: nil, now: now)
    }

    func testOnlyTheWornHatCanRecordARefusal() {
        var batch = AutoSwitchWatch.Batch()
        AutoSwitchWatch.record(.refused(401), for: "worn", in: &batch, isWearing: true)
        AutoSwitchWatch.record(.refused(401), for: "parked", in: &batch, isWearing: false)

        XCTAssertEqual(batch.refused, ["worn"],
                       "a parked token is not the one in use: it stops being refreshed and the "
                           + "server drops it when another account signs in, so 401 on it says "
                           + "nothing about whether wearing the hat would work. Counting it locked "
                           + "the hat out of the very switch that would renew it")
        XCTAssertEqual(batch.troubles.keys.sorted(), ["parked", "worn"],
                       "both are still reported on the row")
    }

    func testARefusedHatIsNotOfferedToAutoSwitch() {
        var refused = healthyHat(id: "refused")
        refused.authRefusedAt = now.addingTimeInterval(-60)
        let healthy = healthyHat(id: "healthy")

        let rows = [row(refused), row(healthy)]

        XCTAssertEqual(AutoSwitchEngine.eligible(in: rows), [healthy.id],
                       "auto-switch must not put on a hat whose token the API has already refused")
    }

    func testTheCopyNamesTheRefusalRatherThanCallingItAnExpiry() {
        var hat = healthyHat()
        hat.authRefusedAt = now.addingTimeInterval(-60)

        XCTAssertEqual(HatsCopy.blocker(for: hat, now: now), "login refused — needs logging in again")
    }

    private func accountStoreSource() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/AccountStore.swift")

        return try String(contentsOf: source, encoding: .utf8)
    }

    private func body(of function: String, in source: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: function)).upperBound
        let rest = source[start...]
        let end = try XCTUnwrap(rest.range(of: "\n    }")).upperBound

        return String(rest[..<end])
    }

    func testStoringACredentialDoesNotForgetThatItWasRefused() throws {
        let source = try accountStoreSource()

        XCTAssertFalse(try body(of: "func noteStored(", in: source).contains("authRefusedAt"),
                       "park() stores the OUTGOING credential through noteStored — the same blob "
                           + "that may have just been refused — so clearing the mark there made the "
                           + "app forget. Measured live on 2026-09-09: auth.refused at 13:36:54, "
                           + "park.outgoing five seconds later, and at 16:32 auto-switch wore that "
                           + "dead hat and cost a login. testARefusedHatIsNotOfferedToAutoSwitch "
                           + "already asserted the intent; nothing kept its input")
    }

    func testOnlyClaimingTheLiveLoginClearsTheRefusal() throws {
        let source = try accountStoreSource()

        XCTAssertTrue(try body(of: "func noteTheLiveLoginWasClaimed(", in: source)
            .contains("authRefusedAt = nil"),
                      "a refusal is spent by a login or a successful read, and capture is where "
                          + "this app learns the live credential belongs to a hat")
        XCTAssertTrue(try body(of: "func capture(\n", in: source)
            .contains("noteTheLiveLoginWasClaimed"),
                      "and every reconcile path reaches that one capture, so the clearing stays in "
                          + "exactly one place")
    }
}
