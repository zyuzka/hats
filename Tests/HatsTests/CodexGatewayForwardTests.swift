import XCTest
@testable import Hats

final class CodexGatewayForwardTests: CodexGatewayTestCase {
    func testATurnReachesTheUpstreamUnderTheWornHatWithEverythingElseAsSent() throws {
        wear("hat-work", workLogin)

        let reply = ask(headers: ["session-id": "thread-1", "originator": "codex_cli_rs", "content-encoding": "zstd"])

        XCTAssertEqual(reply.status, 200)
        let request = try XCTUnwrap(lastSeen)
        XCTAssertEqual(request.path, "/backend-api/codex/responses")
        XCTAssertEqual(request.headers["authorization"], "Bearer " + token(workLogin))
        XCTAssertEqual(request.headers["chatgpt-account-id"], CodexFixture.work.account)
        XCTAssertEqual(request.headers["originator"], "codex_cli_rs")
        XCTAssertEqual(request.headers["content-encoding"], "zstd")
        XCTAssertEqual(request.body, #"{"input":[]}"#, "the body goes byte for byte")
    }

    func testTheHatChangesBetweenRequestsNotInsideAStream() throws {
        wear("hat-work", workLogin)
        answers = { _ in .stream(chunks: ["data: one\n\n", "data: two\n\n", "data: three\n\n"], gap: 0.3) }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(secret)/codex/responses")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        let first = expectation(description: "stream")
        var streamed = ""
        URLSession.shared.dataTask(with: request) { data, _, _ in
            streamed = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            first.fulfill()
        }.resume()
        let deadline = Date().addingTimeInterval(5)
        while seen.value.isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        wear("hat-personal", personalLogin)
        wait(for: [first], timeout: 20)

        XCTAssertEqual(streamed, "data: one\n\ndata: two\n\ndata: three\n\n", "the stream finished on the old hat")
        XCTAssertEqual(seen.value.first?.headers["authorization"], "Bearer " + token(workLogin))
        answers = { _ in .fixed(status: 200, headers: [:], body: "{}") }
        _ = ask()
        XCTAssertEqual(lastSeen?.headers["authorization"], "Bearer " + token(personalLogin))
        XCTAssertEqual(lastSeen?.headers["chatgpt-account-id"], CodexFixture.personal.account)
    }

    func testARequestWithoutTheSecretIsNotFoundAndNeverForwarded() {
        wear("hat-work", workLogin)
        XCTAssertEqual(ask(secret: "wrong").status, 404)
        XCTAssertEqual(ask(secret: String(secret.dropLast()) + "0").status, 404)
        XCTAssertTrue(seen.value.isEmpty, "the upstream was not called")
    }

    func testAWebSocketHandshakeGetsUpgradeRequiredBeforeAnything() throws {
        wear("hat-work", workLogin)
        let answer = try RawHTTPClient.send([
            "GET /\(secret)/codex/responses HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
            "Sec-WebSocket-Version: 13",
            "",
            "",
        ].joined(separator: "\r\n"), toPort: port)

        XCTAssertTrue(answer.hasPrefix("HTTP/1.1 426"), String(answer.prefix(40)))
        XCTAssertTrue(seen.value.isEmpty)
    }

    func testVoiceModeAndOtherPathsAreNotFoundWhileTheModelPathsAreForwarded() {
        wear("hat-work", workLogin)
        XCTAssertEqual(ask("codex/realtime/calls").status, 404)
        XCTAssertTrue(seen.value.isEmpty)
        XCTAssertEqual(ask("codex/images/generations").status, 200)
        XCTAssertEqual(lastSeen?.headers["authorization"], "Bearer " + token(workLogin))
        XCTAssertEqual(ask("codex/alpha/search").status, 200)
        XCTAssertEqual(lastSeen?.path, "/backend-api/codex/alpha/search")
        XCTAssertEqual(ask("codex/models?client_version=0.169.0", method: "GET").status, 200)
        XCTAssertEqual(lastSeen?.path, "/backend-api/codex/models")
    }

    func testWithNoHatWornCodexIsToldSoAndNothingIsForwarded() {
        let reply = ask()
        XCTAssertEqual(reply.status, 400, "a 400 is final for Codex; a 401 would send it after its own login")
        XCTAssertTrue(reply.body.contains("no Codex hat is worn"))
        XCTAssertTrue(seen.value.isEmpty)
    }

    func testATurnStateIssuedUnderOneHatNeverReachesAnother() throws {
        wear("hat-work", workLogin)
        answers = { _ in .fixed(status: 200, headers: ["x-codex-turn-state": "turn-of-work"], body: "{}") }
        _ = ask()
        _ = ask(headers: ["x-codex-turn-state": "turn-of-work"])
        XCTAssertEqual(lastSeen?.headers["x-codex-turn-state"], "turn-of-work", "the same hat keeps its routing")

        wear("hat-personal", personalLogin)
        _ = ask(headers: ["x-codex-turn-state": "turn-of-work"])
        XCTAssertNil(lastSeen?.headers["x-codex-turn-state"], "the value from work is not sent under personal")
        _ = ask(headers: ["x-codex-turn-state": "never-issued"])
        XCTAssertNil(lastSeen?.headers["x-codex-turn-state"])
    }

    func testTheUsageHeadersAreKeptPerHat() throws {
        wear("hat-work", workLogin)
        answers = { _ in
            .fixed(status: 200, headers: [
                "x-codex-primary-window-minutes": "300", "x-codex-primary-used-percent": "12",
                "x-codex-secondary-window-minutes": "10080", "x-codex-secondary-used-percent": "40",
            ], body: "{}")
        }
        _ = ask()
        XCTAssertEqual(state.reading(for: "hat-work")?.window(minutes: 10080)?.percent, 40)
        XCTAssertNil(state.reading(for: "hat-personal"))
    }

    func testTheThreadsThatWentThroughAreNamedForTheBuildGuard() throws {
        wear("hat-work", workLogin)
        _ = ask(headers: ["session-id": "019a-thread-b"])
        _ = ask(headers: ["session-id": "019a-thread-a"])
        _ = ask(headers: ["session-id": "019a-thread-b"])
        let answer = try RawHTTPClient.send([
            "GET /\(secret)/__gateway__/sessions-at-risk HTTP/1.1", "Host: 127.0.0.1:\(port)",
            "Connection: close", "", "",
        ].joined(separator: "\r\n"), toPort: port)

        XCTAssertTrue(answer.hasSuffix("readable 1\ncodex-thread 019a-thread-a\ncodex-thread 019a-thread-b\n"),
                      String(answer.suffix(120)))
        XCTAssertEqual(seen.value.count, 3, "the control path is answered here and not forwarded")
    }
}
