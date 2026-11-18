import XCTest
@testable import Hats

final class CodexGatewayRefusalTests: CodexGatewayTestCase {
    private func refusingWork(status: Int, body: String) {
        answers = { [unowned self] request in
            request.headers["authorization"] == "Bearer " + token(workLogin)
                ? .fixed(status: status, headers: ["x-codex-primary-window-minutes": "300",
                                                   "x-codex-primary-used-percent": "100"], body: body)
                : .fixed(status: 200, headers: [:], body: #"{"on":"personal"}"#)
        }
    }

    func testAUsageLimitOnTheWornHatIsRetriedOnTheNextAndCodexNeverSeesIt() throws {
        wear("hat-work", workLogin)
        refusingWork(status: 429, body: Self.limitBody())
        broker.onLimit = { [unowned self] _, _ in wear("hat-personal", personalLogin) }

        let reply = ask()

        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(reply.body, #"{"on":"personal"}"#)
        XCTAssertEqual(broker.limitCalls.value, [["hat-work"]])
        XCTAssertEqual(seen.value.map { $0.headers["chatgpt-account-id"] },
                       [CodexFixture.work.account, CodexFixture.personal.account])
        XCTAssertEqual(seen.value.map(\.body), [#"{"input":[]}"#, #"{"input":[]}"#], "the same body is sent again")
        XCTAssertEqual(state.reading(for: "hat-work")?.window(minutes: 300)?.percent, 100)
    }

    func testWithNothingToRetryOnTheUsageLimitReachesCodexAsItCame() {
        wear("hat-work", workLogin)
        refusingWork(status: 429, body: Self.limitBody())

        let reply = ask()

        XCTAssertEqual(reply.status, 429)
        XCTAssertEqual(reply.body, Self.limitBody())
        XCTAssertEqual(seen.value.count, 1)
    }

    func testEveryHatIsTriedAtMostOncePerRequest() {
        wear("hat-work", workLogin)
        answers = { _ in .fixed(status: 429, headers: [:], body: Self.limitBody()) }
        broker.onLimit = { [unowned self] _, tried in
            tried.contains("hat-personal") ? wear("hat-work", workLogin) : wear("hat-personal", personalLogin)
        }

        let reply = ask()

        XCTAssertEqual(reply.status, 429, "work already refused in this request, so it is not asked again")
        XCTAssertEqual(broker.limitCalls.value, [["hat-work"], ["hat-work", "hat-personal"]])
        XCTAssertEqual(seen.value.count, 2)
    }

    func testOtherRefusalsReachCodexAsTheyCame() {
        wear("hat-work", workLogin)
        for (status, body) in [(429, Self.limitBody("insufficient_quota")), (429, "not json"),
                               (403, Self.limitBody("invalid_workspace_selected")), (503, "{}")] {
            refusingWork(status: status, body: body)
            let reply = ask()
            XCTAssertEqual(reply.status, status)
            XCTAssertEqual(reply.body, body)
        }
        XCTAssertEqual(broker.limitCalls.value, [], "only usage_limit_reached moves the hat")
        XCTAssertEqual(broker.unauthorizedCalls.value, [])
    }

    func testAnUnauthorizedAnswerIsRecoveredOnceAndNeverReachesCodex() {
        wear("hat-work", workLogin)
        let renewed = CodexFixture.login(CodexFixture.work, refresh: "work-2")
        answers = { [unowned self] request in
            request.headers["authorization"] == "Bearer " + token(renewed)
                ? .fixed(status: 200, headers: [:], body: "{}")
                : .fixed(status: 401, headers: [:], body: #"{"error":{"type":"invalid_token"}}"#)
        }
        broker.onUnauthorized = { [unowned self] _ in wear("hat-work", renewed).map { .retry($0) } ?? .needsSignIn }

        XCTAssertEqual(ask().status, 200)
        XCTAssertEqual(broker.unauthorizedCalls.value, ["hat-work"])
    }

    func testASecondUnauthorizedBecomesAFinalHatsRefusalAndMarksTheHat() {
        wear("hat-work", workLogin)
        answers = { _ in .fixed(status: 401, headers: [:], body: "{}") }
        broker.onUnauthorized = { [unowned self] _ in state.login.map { .retry($0) } ?? .needsSignIn }

        let reply = ask()

        XCTAssertEqual(reply.status, 400, "Codex does not retry a 400, and never sees a 401")
        XCTAssertTrue(reply.body.contains("needs a sign-in"), reply.body)
        XCTAssertTrue(reply.body.contains("invalid_request_error"))
        XCTAssertEqual(broker.unauthorizedCalls.value, ["hat-work"])
        XCTAssertEqual(broker.refusedAgainCalls.value, ["hat-work"])
        XCTAssertEqual(seen.value.count, 2)
    }

    func testARenewalThatFailsIsAFinalHatsRefusal() {
        wear("hat-work", workLogin)
        answers = { _ in .fixed(status: 401, headers: [:], body: "{}") }

        XCTAssertEqual(ask().status, 400)
        XCTAssertEqual(seen.value.count, 1)
    }

    func testATooLargeLimitAnswerIsPassedOnWithoutMovingTheHat() {
        wear("hat-work", workLogin)
        let huge = #"{"error":{"type":"usage_limit_reached","pad":""# + String(repeating: "x", count: 70_000) + "\"}}"
        refusingWork(status: 429, body: huge)
        broker.onLimit = { [unowned self] _, _ in wear("hat-personal", personalLogin) }

        let reply = ask()

        XCTAssertEqual(reply.status, 429)
        XCTAssertEqual(reply.body.count, huge.count, "the whole answer still reaches Codex")
        XCTAssertEqual(broker.limitCalls.value, [])
    }

    func testALimitAnswerThatStallsIsPassedOnAfterTheWait() {
        gateway.holdWait = 0.3
        wear("hat-work", workLogin)
        answers = { _ in .heldOpen(status: 429, body: #"{"error":{"type":"usage_li"#) }
        broker.onLimit = { [unowned self] _, _ in wear("hat-personal", personalLogin) }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(secret)/codex/responses")!)
        request.httpMethod = "POST"
        var status = 0
        let waiter = expectation(description: "head")
        let task = URLSession.shared.dataTask(with: request)
        let observer = task.observe(\.response) { task, _ in
            guard let http = task.response as? HTTPURLResponse else { return }
            status = http.statusCode
            waiter.fulfill()
        }
        task.resume()
        wait(for: [waiter], timeout: 5)
        observer.invalidate()
        task.cancel()

        XCTAssertEqual(status, 429)
        XCTAssertEqual(broker.limitCalls.value, [], "a body that was not read whole moves nothing")
    }
}
