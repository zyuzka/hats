import XCTest
@testable import Hats

final class CodexGatewaySlowBrokerTests: CodexGatewayTestCase {
    func testASlowDecisionOnAUsageLimitIsTheOnlyThingThatAnswersCodex() {
        gateway.holdWait = 0.2
        broker.delay = 0.6
        wear("hat-work", workLogin)
        answers = { [unowned self] request in
            request.headers["authorization"] == "Bearer " + token(workLogin)
                ? .fixed(status: 429, headers: [:], body: Self.limitBody())
                : .fixed(status: 200, headers: [:], body: #"{"on":"personal"}"#)
        }
        broker.onLimit = { [unowned self] _, _ in wear("hat-personal", personalLogin) }

        let reply = ask()

        XCTAssertEqual(reply.status, 200, "the hold timer did not answer while the broker was still deciding")
        XCTAssertEqual(reply.body, #"{"on":"personal"}"#)
    }

    func testASlowRenewalAfterA401IsNotCutShortAndDoesNotMarkTheHat() {
        gateway.holdWait = 0.2
        broker.delay = 0.6
        wear("hat-work", workLogin)
        let renewed = CodexFixture.login(CodexFixture.work, refresh: "work-2")
        answers = { [unowned self] request in
            request.headers["authorization"] == "Bearer " + token(renewed)
                ? .fixed(status: 200, headers: [:], body: "{}")
                : .fixed(status: 401, headers: [:], body: "{}")
        }
        broker.onUnauthorized = { [unowned self] _ in wear("hat-work", renewed).map { .retry($0) } ?? .needsSignIn }

        XCTAssertEqual(ask().status, 200)
        XCTAssertEqual(broker.unauthorizedCalls.value, ["hat-work"])
        XCTAssertEqual(broker.refusedAgainCalls.value, [], "no second recovery marked the hat mid-renewal")
    }

    func testA401FromTheHatTheRequestMovedToGetsItsOwnRenewal() {
        wear("hat-work", workLogin)
        let personalRenewed = CodexFixture.login(CodexFixture.personal, refresh: "personal-2")
        answers = { [unowned self] request in
            request.headers["authorization"] == "Bearer " + token(personalRenewed)
                ? .fixed(status: 200, headers: [:], body: "{}")
                : .fixed(status: 401, headers: [:], body: "{}")
        }
        broker.onUnauthorized = { [unowned self] refused in
            let next = refused.hatID == "hat-work"
                ? wear("hat-personal", personalLogin) : wear("hat-personal", personalRenewed)
            return next.map { .retry($0) } ?? .needsSignIn
        }

        XCTAssertEqual(ask().status, 200)
        XCTAssertEqual(broker.unauthorizedCalls.value, ["hat-work", "hat-personal"])
        XCTAssertEqual(broker.refusedAgainCalls.value, [])
    }

    func testA401WhoseBodyStallsGoesToRecoveryAndCodexNeverSeesA401() {
        gateway.holdWait = 0.2
        wear("hat-work", workLogin)
        let renewed = CodexFixture.login(CodexFixture.work, refresh: "work-2")
        answers = { [unowned self] request in
            request.headers["authorization"] == "Bearer " + token(renewed)
                ? .fixed(status: 200, headers: [:], body: "{}")
                : .heldOpen(status: 401, body: #"{"error":"#)
        }
        broker.onUnauthorized = { [unowned self] _ in wear("hat-work", renewed).map { .retry($0) } ?? .needsSignIn }

        XCTAssertEqual(ask().status, 200)
        XCTAssertEqual(broker.unauthorizedCalls.value, ["hat-work"])
    }

    func testAThreadIsAtRiskForSixHoursAfterItsLastRequest() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        state.noteThread("thread-old", at: start)
        state.noteThread("thread-kept", at: start)
        state.noteThread("thread-kept", at: start.addingTimeInterval(4 * 3600))

        XCTAssertEqual(state.threadsAtRisk(at: start.addingTimeInterval(5 * 3600)), ["thread-kept", "thread-old"])
        XCTAssertEqual(state.threadsAtRisk(at: start.addingTimeInterval(7 * 3600)), ["thread-kept"],
                       "a thread silent for over 6 hours no longer holds the build or the quit")
        XCTAssertEqual(state.threadsAtRisk(at: start.addingTimeInterval(11 * 3600)), [])
    }
}
