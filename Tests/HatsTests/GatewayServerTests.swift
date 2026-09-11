import XCTest
@testable import Hats

private final class FakeUpstream: @unchecked Sendable {
    struct Seen {
        let path: String
        let authorization: String?
        let custom: String?
        let body: String
    }

    private let seenBox = Locked<[Seen]>([])

    var seen: [Seen] { seenBox.value }

    private func note(_ entry: Seen) { seenBox.mutate { $0.append(entry) } }
    private let listener: NIOTestListener

    var url: URL { URL(string: "http://127.0.0.1:\(listener.port)")! }

    init() throws {
        listener = NIOTestListener()
        listener.onRequest = { [weak self] request in
            self?.note(Seen(path: request.path,
                                   authorization: request.headers["authorization"],
                                   custom: request.headers["x-custom"],
                                   body: request.body))
            if request.path.hasPrefix("/stall") {
                return .stalled(seconds: 2)
            }
            if request.path.hasPrefix("/stream-long") {
                return .stream(chunks: (0..<40).map { "data: \($0)\n\n" }, gap: 0.1)
            }
            if request.path.hasPrefix("/stream") {
                return .stream(chunks: ["data: 0\n\n", "data: 1\n\n", "data: 2\n\n"],
                               gap: 0.05)
            }
            if request.path.hasPrefix("/401") {
                return .fixed(status: 401, headers: ["X-Upstream-Marker": "kept"],
                              body: #"{"type":"error"}"#)
            }
            return .fixed(status: 200, headers: ["X-Upstream-Marker": "kept"],
                          body: #"{"echo":"ok"}"#)
        }
        try listener.start()
    }

    func stop() { listener.stop() }

    var disconnects: Int { listener.disconnects }
}

private final class ArrivalRecorder: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Arrival {
        let at: Date
        let text: String
    }

    let finished = XCTestExpectation(description: "the streamed answer ends")
    private let lock = NSLock()
    private var arrivals: [Arrival] = []
    private var contentType: String?

    var recorded: [Arrival] {
        lock.lock()
        defer { lock.unlock() }
        return arrivals
    }

    var announcedContentType: String? {
        lock.lock()
        defer { lock.unlock() }
        return contentType
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        arrivals.append(Arrival(at: Date(), text: String(decoding: data, as: UTF8.self)))
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finished.fulfill()
    }
}

final class GatewayServerTests: XCTestCase {
    private var upstream: FakeUpstream!
    private var gateway: GatewayServer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        upstream = try FakeUpstream()
        gateway = GatewayServer(port: 0, refusal: nil, upstream: upstream.url)
        try gateway.start()
    }

    override func tearDown() {
        gateway?.stop()
        upstream?.stop()
        super.tearDown()
    }

    private var base: URL { URL(string: "http://127.0.0.1:\(gateway.boundPort ?? 0)")! }

    private func post(_ path: String, body: String = "{}",
                      headers: [String: String] = [:]) -> (Int, [String: String], String) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        var status = 0
        var responseHeaders: [String: String] = [:]
        var payload = ""
        let waiter = expectation(description: path)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                status = http.statusCode
                for (key, value) in http.allHeaderFields {
                    if let key = key as? String, let value = value as? String {
                        responseHeaders[key] = value
                    }
                }
            }
            payload = String(data: data ?? Data(), encoding: .utf8) ?? ""
            waiter.fulfill()
        }.resume()
        wait(for: [waiter], timeout: 15)
        return (status, responseHeaders, payload)
    }

    func testARequestReachesTheUpstreamUnchanged() {
        let (status, headers, body) = post("/v1/messages", body: #"{"hi":1}"#, headers: [
            "Authorization": "Bearer sk-test-AAA",
            "X-Custom": "keep-me",
        ])

        XCTAssertEqual(status, 200)
        XCTAssertEqual(body, #"{"echo":"ok"}"#)
        XCTAssertEqual(headers["X-Upstream-Marker"], "kept",
                       "the upstream's own headers must survive")
        XCTAssertEqual(upstream.seen.count, 1)
        XCTAssertEqual(upstream.seen.first?.authorization, "Bearer sk-test-AAA",
                       "the credential is forwarded untouched")
        XCTAssertEqual(upstream.seen.first?.custom, "keep-me")
        XCTAssertEqual(upstream.seen.first?.body, #"{"hi":1}"#)
    }

    func testAContentEncodingHeaderIsNotRelayedOverAnAlreadyDecodedBody() {
        let upstream: [AnyHashable: Any] = [
            "Content-Encoding": "gzip",
            "Content-Length": "97",
            "Content-Type": "application/json",
            "Transfer-Encoding": "chunked",
            "Trailer": "Expires",
            "Connection": "keep-alive",
            "X-Request-Id": "abc",
        ]

        let relayed = UpstreamRelay.relayedHeaders(from: upstream)
        let names = Set(relayed.map { $0.0.lowercased() })

        XCTAssertFalse(names.contains("content-encoding"),
                       "URLSession hands over a decoded body, so claiming it is still "
                       + "encoded makes the client fail with a decompression error")
        XCTAssertFalse(names.contains("content-length"), "the relayed length is unknown")
        XCTAssertFalse(names.contains("transfer-encoding"), "framing is NIO's own")
        XCTAssertFalse(names.contains("trailer"),
                       "RFC 7230 spells the hop-by-hop header Trailer, singular")
        XCTAssertFalse(names.contains("connection"), "hop-by-hop belongs to the hop")
        XCTAssertEqual(names, ["content-type", "x-request-id"],
                       "everything else the upstream said survives")
    }

    func testTheGatewayErrorBodyIsValidJSONWhateverTheReasonSays() {
        let hostile = "quote \" backslash \\ newline \n tab \t control \u{7}"

        let body = GatewayErrorBody.describing(hostile)
        let object = try? JSONSerialization.jsonObject(with: body)

        guard let parsed = object as? [String: Any] else {
            XCTFail("a reason with quotes or escapes must not break the JSON")
            return
        }
        let error = parsed["error"] as? [String: Any]
        XCTAssertEqual(error?["type"] as? String, "api_error")
        XCTAssertEqual(error?["message"] as? String, "gateway: " + hostile,
                       "the reason survives escaping unchanged")
    }

    func testARequestTargetCannotRedirectTheGatewayOffItsUpstream() {
        let upstream = URL(string: "https://api.anthropic.com")!

        let cases: [(target: String, expected: String?, why: String)] = [
            ("/v1/messages", "https://api.anthropic.com/v1/messages", "an ordinary path"),
            ("/v1/messages?beta=true", "https://api.anthropic.com/v1/messages?beta=true",
             "a query survives"),
            ("http://169.254.169.254/latest/meta-data", nil,
             "a target naming another host is refused, not quietly rewritten"),
            ("https://evil.example/v1/messages", nil,
             "including one that looks like the real thing"),
            ("//evil.example/v1/messages", nil,
             "a protocol-relative target names a host too"),
            ("v1/messages", nil, "a target that is not a path is refused"),
        ]

        for testCase in cases {
            let built = GatewayForward.upstreamURL(for: testCase.target, upstream: upstream)
            XCTAssertEqual(built?.absoluteString, testCase.expected, testCase.why)
            if let built {
                XCTAssertEqual(built.host, "api.anthropic.com",
                               "the gateway must never reach another host")
            }
        }
    }

    func testARepeatedRequestHeaderReachesTheUpstreamWithBothValues() throws {
        let raw = [
            "POST /v1/messages HTTP/1.1",
            "Host: 127.0.0.1:\(gateway.boundPort ?? 0)",
            "Authorization: Bearer one",
            "X-Custom: first",
            "X-Custom: second",
            "Content-Length: 2",
            "Connection: close",
            "",
            "{}",
        ].joined(separator: "\r\n")

        let answer = try RawHTTPClient.send(raw, toPort: gateway.boundPort ?? 0)

        XCTAssertTrue(answer.hasPrefix("HTTP/1.1 200"), String(answer.prefix(40)))
        XCTAssertEqual(upstream.seen.first?.custom, "first,second",
                       "a header the client repeated must not lose its first value on the way")
    }

    func testAnUpstreamErrorArrivesAsItself() {
        let (status, headers, _) = post("/401", headers: ["Authorization": "Bearer x"])
        XCTAssertEqual(status, 401, "an upstream 401 is not swallowed into a gateway error")
        XCTAssertEqual(headers["X-Upstream-Marker"], "kept")
    }

    func testAStreamedAnswerArrivesAsItIsWrittenNotWhenItEnds() {
        let recorder = ArrivalRecorder()
        let client = URLSession(configuration: .ephemeral, delegate: recorder, delegateQueue: nil)
        defer { client.finishTasksAndInvalidate() }
        var request = URLRequest(url: base.appendingPathComponent("/stream"))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer sk-test-AAA", forHTTPHeaderField: "Authorization")

        client.dataTask(with: request).resume()
        wait(for: [recorder.finished], timeout: 15)

        let arrivals = recorder.recorded
        let spread = (arrivals.last?.at ?? .distantPast)
            .timeIntervalSince(arrivals.first?.at ?? .distantPast)
        XCTAssertEqual(recorder.announcedContentType, "text/event-stream",
                       "the upstream's own content type survives the relay")
        XCTAssertEqual(arrivals.map(\.text).joined(), "data: 0\n\ndata: 1\n\ndata: 2\n\n",
                       "every event arrives, in order")
        XCTAssertGreaterThanOrEqual(arrivals.count, 2,
                                    "events written 50 ms apart must not arrive as one block")
        XCTAssertGreaterThanOrEqual(spread, 0.05,
                                    "three events written 50 ms apart arrive spread out, "
                                    + "measured \(spread) s between the first and the last")
    }

    func testAClientThatHangsUpMidStreamTakesTheUpstreamRequestDownWithIt() throws {
        let raw = [
            "POST /stream-long HTTP/1.1",
            "Host: 127.0.0.1:\(gateway.boundPort ?? 0)",
            "Authorization: Bearer one",
            "Content-Length: 2",
            "",
            "{}",
        ].joined(separator: "\r\n")
        let before = upstream.disconnects
        let client = try RawHTTPClient.Connection(port: gateway.boundPort ?? 0)
        try client.send(raw)
        try client.waitUntilTheBodyStarts()

        client.hangUp()

        XCTAssertEqual(disconnectsSeen(by: upstream, after: before, within: 1.5), before + 1,
                       "the upstream must see its client leave within moments of the real client leaving; "
                       + "a stream nobody is reading is tokens nobody asked for")
        XCTAssertEqual(gateway.ledger.failureCount, 0, "a client hanging up is not an upstream failure")
    }

    func testAHangUpBeforeTheHeadCancelsTheTaskButURLSessionKeepsTheSocketUntilTheAnswer() throws {
        let raw = [
            "POST /stall HTTP/1.1",
            "Host: 127.0.0.1:\(gateway.boundPort ?? 0)",
            "Authorization: Bearer one",
            "Content-Length: 2",
            "",
            "{}",
        ].joined(separator: "\r\n")
        let seen = upstream.seen.count
        let before = upstream.disconnects
        let client = try RawHTTPClient.Connection(port: gateway.boundPort ?? 0)
        try client.send(raw)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, upstream.seen.count == seen { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertEqual(upstream.seen.count, seen + 1, "the upstream is holding the request when the client leaves")

        client.hangUp()

        XCTAssertEqual(disconnectsSeen(by: upstream, after: before, within: 1.0), before,
                       "measured: URLSession keeps the socket open after a cancel that arrives before any "
                       + "response byte, so the upstream learns nothing until it answers — the door still open")
        XCTAssertEqual(disconnectsSeen(by: upstream, after: before, within: 3.0), before + 1,
                       "once the stalled answer arrives the connection is released, not kept for reuse")
        XCTAssertEqual(gateway.ledger.failureCount, 0,
                       "the cancellation the hang-up caused is the client's choice, not an upstream failure")
    }

    private func disconnectsSeen(by upstream: FakeUpstream, after before: Int, within seconds: TimeInterval) -> Int {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, upstream.disconnects == before { Thread.sleep(forTimeInterval: 0.02) }
        return upstream.disconnects
    }

    func testTheControlPathIsAnsweredLocally() {
        _ = post("/v1/messages", headers: ["Authorization": "Bearer sk-test-AAA"])
        let before = upstream.seen.count

        let (status, _, body) = post(GatewayPaths.control)

        XCTAssertEqual(status, 200)
        XCTAssertEqual(upstream.seen.count, before, "status must not reach the upstream")
        XCTAssertTrue(body.contains("\"requests\""), body)
        XCTAssertFalse(body.contains("sk-test-AAA"), "a token must never be reported")
    }

    func testAnUnreachableUpstreamIsTheGatewaysOwnFailure() throws {
        let dead = GatewayServer(port: 0, refusal: nil,
                                 upstream: URL(string: "http://127.0.0.1:9")!)
        try dead.start()
        defer { dead.stop() }

        var request = URLRequest(url: URL(string:
            "http://127.0.0.1:\(dead.boundPort ?? 0)/v1/messages")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer y", forHTTPHeaderField: "Authorization")

        var status = 0
        var payload = ""
        let waiter = expectation(description: "dead upstream")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            payload = String(data: data ?? Data(), encoding: .utf8) ?? ""
            waiter.fulfill()
        }.resume()
        wait(for: [waiter], timeout: 20)

        XCTAssertEqual(status, 502)
        XCTAssertTrue(payload.contains("gateway:"), "the body names which side failed")
        XCTAssertEqual(dead.ledger.failureCount, 1)
    }

    func testAfterASwitchEachSessionIsRefusedOnceThroughTheServedGateway() throws {
        let refusal = GatewayRefusal(settle: 0, account: "a@x.co")
        let served = GatewayServer(port: 0, refusal: refusal, upstream: upstream.url)
        try served.start()
        defer { served.stop() }

        func ask(session: String, token: String) -> Int {
            var request = URLRequest(url: URL(string:
                "http://127.0.0.1:\(served.boundPort ?? 0)/v1/messages")!)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue(session, forHTTPHeaderField: GatewayPaths.sessionHeader)
            var status = 0
            let waiter = expectation(description: session + token)
            URLSession.shared.dataTask(with: request) { _, response, _ in
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
                waiter.fulfill()
            }.resume()
            wait(for: [waiter], timeout: 15)
            return status
        }

        let before = ask(session: "S1", token: "one")
        refusal.hasSwitched(to: "b@x.co")
        let refused = ask(session: "S1", token: "one")
        let retry = ask(session: "S1", token: "minted")
        let second = ask(session: "S2", token: "one")

        XCTAssertEqual(before, 200, "before a switch the gateway forwards")
        XCTAssertEqual(refused, 401, "after a switch the session gets one 401")
        XCTAssertEqual(retry, 200, "its retry with a fresh token is forwarded")
        XCTAssertEqual(second, 401, "a second session is refused once as well")
        XCTAssertEqual(refusal.snapshot().sessionsMoved, 2)
    }
}
