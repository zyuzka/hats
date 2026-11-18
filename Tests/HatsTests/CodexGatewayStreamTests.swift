import XCTest
@testable import Hats

final class CodexGatewayStreamTests: CodexGatewayTestCase {
    func testAFailureInsideTheStreamReachesCodexAsItCameWithoutARetry() {
        wear("hat-work", workLogin)
        let created = "event: response.created\ndata: {\"type\":\"response.created\"}\n\n"
        let failed = "event: response.failed\ndata: {\"type\":\"response.failed\"}\n\n"
        answers = { _ in .stream(chunks: [created, failed], gap: 0.05) }
        broker.onLimit = { [unowned self] _, _ in wear("hat-personal", personalLogin) }

        let reply = ask()

        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(reply.body, created + failed)
        XCTAssertEqual(seen.value.count, 1, "nothing is repeated once Codex got the first byte")
        XCTAssertEqual(broker.limitCalls.value, [])
        XCTAssertEqual(broker.unauthorizedCalls.value, [])
    }

    func testALimitAnswerCutOffMidBodyIsPassedOnWithoutMovingTheHat() {
        wear("hat-work", workLogin)
        answers = { _ in .cutOff(status: 429, body: Self.limitBody()) }
        broker.onLimit = { [unowned self] _, _ in wear("hat-personal", personalLogin) }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(secret)/codex/responses")!)
        request.httpMethod = "POST"
        var status = 0
        let waiter = expectation(description: "answer")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            waiter.fulfill()
        }.resume()
        wait(for: [waiter], timeout: 15)

        XCTAssertEqual(broker.limitCalls.value, [], "a body that broke off is not read as a usage limit")
        XCTAssertEqual(seen.value.count, 1)
        XCTAssertNotEqual(status, 200, "nothing was retried on another hat")
    }

    func testANetworkFailureWhileRenewingIsABadGatewayNotASignIn() {
        wear("hat-work", workLogin)
        answers = { _ in .fixed(status: 401, headers: [:], body: "{}") }
        broker.onUnauthorized = { _ in .unreachable }

        let reply = ask()

        XCTAssertEqual(reply.status, 502, "Codex repeats a 5xx by itself")
        XCTAssertTrue(reply.body.contains("could not be renewed"), reply.body)
        XCTAssertFalse(reply.body.contains("needs a sign-in"))
        XCTAssertEqual(broker.refusedAgainCalls.value, [], "the hat is not marked")
    }

    func testAfterAChangeEveryModelRequestCarriesTheNewHatAndNothingElseIsForwarded() {
        wear("hat-work", workLogin)
        _ = ask()
        wear("hat-personal", personalLogin)

        _ = ask()
        XCTAssertEqual(lastSeen?.headers["authorization"], "Bearer " + token(personalLogin))
        _ = ask("codex/models?client_version=0.169.0", method: "GET")
        XCTAssertEqual(lastSeen?.headers["authorization"], "Bearer " + token(personalLogin))
        XCTAssertEqual(ask("wham/usage", method: "GET").status, 404,
                       "the service's chatgpt_base_url requests are not the gateway's")
        XCTAssertEqual(seen.value.count, 3)
    }

    func testTheUsageOfEachAnswerIsWrittenToTheJournal() throws {
        let reading = CodexUsageReading(
            windows: [CodexUsageWindow(minutes: 300, percent: 7, resetsAt: nil),
                      CodexUsageWindow(minutes: 10080, percent: 41, resetsAt: nil)],
            plan: "plus"
        )
        XCTAssertEqual(CodexUsageHeaders.journalEntry(hatID: "hat-work-0123", reading: reading),
                       ["hat": "hat-work", "windows": "300m=7%,10080m=41%", "plan": "plus"])
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/CodexGatewayExchange+Decide.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains(
            #"Journal.log("codexGateway.usage", CodexUsageHeaders.journalEntry(hatID: login.hatID, reading: reading))"#
        ), "every answer that carries usage writes it to the journal")
    }
}
