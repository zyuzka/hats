import XCTest
@testable import Hats

private final class Dial {
    private var at = Date(timeIntervalSince1970: 1_788_000_000)

    var now: () -> Date { { [self] in at } }

    func advance(_ by: TimeInterval) { at = at.addingTimeInterval(by) }
}

final class GatewayRefusalTests: XCTestCase {
    private let settle: TimeInterval = 30

    private func armed() -> (GatewayRefusal, Dial) {
        let dial = Dial()
        let refusal = GatewayRefusal(settle: settle, account: "a@x.co", clock: dial.now)
        XCTAssertTrue(refusal.hasSwitched(to: "b@x.co"), "a different account is a switch")
        dial.advance(settle + 1)
        return (refusal, dial)
    }

    func testNothingIsRefusedBeforeASwitchIsSeen() {
        let refusal = GatewayRefusal(settle: settle, account: "a@x.co")
        XCTAssertFalse(refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                          session: "S1"))
    }

    func testAFirstReadableAccountIsABaselineRatherThanASwitch() {
        let dial = Dial()
        let refusal = GatewayRefusal(settle: settle, account: nil, clock: dial.now)

        let baseline = refusal.hasSwitched(to: "a@x.co")
        dial.advance(settle + 1)
        let refusedOnBaseline = refusal.shouldRefuse(
            path: "/v1/messages",
            credential: "aaaaaaaa",
            session: "S1"
        )

        XCTAssertFalse(baseline,
                       "a gateway that started with an unreadable account must take the "
                       + "first reading as its baseline, not as a switch")
        XCTAssertFalse(refusedOnBaseline, "and must not refuse anything for it")

        XCTAssertTrue(refusal.hasSwitched(to: "b@x.co"), "a later change is a switch")
    }

    func testOnlyARealAccountChangeArmsARefusal() {
        let refusal = GatewayRefusal(settle: settle, account: "a@x.co")
        XCTAssertTrue(refusal.hasSwitched(to: "b@x.co"))
        XCTAssertFalse(refusal.hasSwitched(to: "b@x.co"), "the same account is not a switch")
        XCTAssertFalse(refusal.hasSwitched(to: nil), "an unreadable account is not a switch")
        XCTAssertFalse(refusal.hasSwitched(to: ""), "nor an empty one")
    }

    func testARefusalLandsOnlyWhereItIsSafe() {
        let cases: [(path: String, credential: String, expected: Bool, why: String)] = [
            ("/v1/messages", "aaaaaaaa", true, "an inference request with a credential"),
            ("/v1/oauth/token", "aaaaaaaa", false, "a token refresh is never refused"),
            ("/v1/messages", GatewayCredential.none, false, "no credential, no refusal"),
            ("/v1/models", "aaaaaaaa", false, "an unknown path is never refused"),
        ]
        for testCase in cases {
            let (refusal, _) = armed()
            XCTAssertEqual(
                refusal.shouldRefuse(path: testCase.path, credential: testCase.credential,
                                   session: "S1"),
                testCase.expected, testCase.why)
        }
    }

    func testNothingIsRefusedBeforeTheSettleHasElapsed() {
        let (refusal, dial) = armed()
        dial.advance(-2)
        XCTAssertFalse(refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                          session: "S1"),
                       "the settle is the whole of the promise: before it elapses the gateway answers")
    }

    func testEverySessionIsRefusedOnceAndOnlyOnce() {
        let (refusal, _) = armed()

        let first = refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                       session: "S1")
        let retry = refusal.shouldRefuse(path: "/v1/messages", credential: "bbbbbbbb",
                                       session: "S1")
        let other = refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                       session: "S2")
        let otherRetry = refusal.shouldRefuse(path: "/v1/messages", credential: "cccccccc",
                                            session: "S2")

        XCTAssertTrue(first, "the first request of a session after a switch is refused")
        XCTAssertFalse(retry, "a session is not refused twice, whatever token it carries")
        XCTAssertTrue(other, "every session moves, so the second one is refused too")
        XCTAssertFalse(otherRetry, "nor is the second one refused twice")
        XCTAssertEqual(refusal.snapshot().sessionsMoved, 2)
    }

    func testTheLiveRefusalLoopIsOneRefusalNow() {
        let minted = ["10a12dc7", "15bc92e3", "7faf72d5", "f94bd107", "a0ea1bb9",
                      "6db4c236"]
        let (refusal, _) = armed()

        let refused = minted.filter {
            refusal.shouldRefuse(path: "/v1/messages", credential: $0, session: "S1")
        }

        XCTAssertEqual(refused.count, 1, "a loop is back: \(refused)")
    }

    func testARequestWithoutASessionIdIsStillMovedOnce() {
        let (refusal, _) = armed()
        XCTAssertTrue(refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                         session: nil))
        XCTAssertFalse(refusal.shouldRefuse(path: "/v1/messages", credential: "bbbbbbbb",
                                          session: nil))
    }

    func testANewSwitchMovesTheSameSessionAgain() {
        let (refusal, dial) = armed()
        refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa", session: "S1")

        refusal.hasSwitched(to: "a@x.co")
        dial.advance(settle + 1)

        XCTAssertTrue(refusal.shouldRefuse(path: "/v1/messages", credential: "dddddddd",
                                         session: "S1"))
    }

    func testTheSnapshotReportsWhatIsHappening() {
        let dial = Dial()
        let refusal = GatewayRefusal(settle: settle, account: "a@x.co", clock: dial.now)

        let quiet = refusal.snapshot()
        XCTAssertNil(quiet.secondsSinceSwitch, "no switch seen, nothing to report")
        XCTAssertEqual(quiet.account, "a@x.co")

        refusal.hasSwitched(to: "b@x.co")
        let settling = refusal.snapshot()
        XCTAssertTrue(settling.settling, "a switch just seen is still settling")
        XCTAssertEqual(settling.switchedTo, "b@x.co")
        XCTAssertEqual(settling.sessionsMoved, 0)
    }

    func testAFingerprintStandsForATokenWithoutBeingOne() {
        XCTAssertEqual(GatewayCredential.fingerprint(nil), GatewayCredential.none)
        XCTAssertEqual(GatewayCredential.fingerprint(""), GatewayCredential.none)

        XCTAssertEqual(GatewayCredential.fingerprint("Bearer "), GatewayCredential.none,
                       "a scheme with no token is not a credential")
        XCTAssertEqual(GatewayCredential.fingerprint("Bearer    "),
                       GatewayCredential.none, "nor is one padded with spaces")

        let first = GatewayCredential.fingerprint("Bearer aaa")
        XCTAssertEqual(first, GatewayCredential.fingerprint("Bearer aaa"))
        XCTAssertNotEqual(first, GatewayCredential.fingerprint("Bearer bbb"))
        XCTAssertEqual(first.count, 8)
        XCTAssertFalse(first.contains("aaa"))
    }

    func testOnlyTheInferencePathsCountAsInference() {
        XCTAssertTrue(GatewayPaths.isInference("/v1/messages"))
        XCTAssertTrue(GatewayPaths.isInference("/v1/messages?beta=true"))
        XCTAssertTrue(GatewayPaths.isInference("/v1/complete"))
        XCTAssertFalse(GatewayPaths.isInference("/v1/oauth/token"))
        XCTAssertFalse(GatewayPaths.isInference("/v1/organizations/usage"))
    }

    func testASessionKeyIsASCIIAndNotAnyAlphanumericUnicodeKnows() {
        XCTAssertEqual(GatewayRefusal.sessionKey("0bb0a1f2-3c4d_5e6f"), "0bb0a1f2-3c4d_5e6f",
                       "a real id is ASCII hex with dashes and underscores, and passes through")

        for homoglyph in ["0bb0а1f2", "0bb0１f2", "0bb0٢f2", "0bb0Ⅶf2"] {
            let key = GatewayRefusal.sessionKey(homoglyph)
            XCTAssertFalse(key.unicodeScalars.contains { !$0.isASCII },
                           "\(homoglyph) came from a client header and becomes a map key and a "
                               + "shortened id in the status body, so a scalar that merely looks "
                               + "like ASCII must not survive into either. This branch already "
                               + "answered the same question for version strings — ASCII digits and "
                               + "not any numeral Unicode knows — and this asked it separately")
            XCTAssertTrue(key.contains("."), "the rejected scalar reads as a dot, as before")
        }
    }
}
