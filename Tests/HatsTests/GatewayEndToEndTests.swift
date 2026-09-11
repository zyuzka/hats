import XCTest
@testable import Hats

final class GatewayEndToEndTests: XCTestCase {
    private static let retiredPort = 4711

    private let upstreamSeenBox = Locked<[String]>([])
    private let foreignSeenBox = Locked<[String]>([])

    private var upstreamSeen: [String] { upstreamSeenBox.value }
    private var foreignSeen: [String] { foreignSeenBox.value }
    private var upstream: NIOTestListener!
    private var foreign: NIOTestListener!
    private var gateway: GatewayServer!
    private var refusal: GatewayRefusal!
    private let accountBox = Locked("filip@x.co")

    private var account: String {
        get { accountBox.value }
        set { accountBox.value = newValue }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        upstreamSeenBox.value = []
        upstream = NIOTestListener()
        upstream.onRequest = { [weak self] request in
            self?.upstreamSeenBox.mutate { $0.append(request.path) }
            return .fixed(status: 200, headers: [:], body: #"{"echo":"ok"}"#)
        }
        try upstream.start()

        foreignSeenBox.value = []
        foreign = NIOTestListener()
        foreign.onRequest = { [weak self] request in
            self?.foreignSeenBox.mutate { $0.append(request.path) }
            return .fixed(status: 200, headers: [:], body: #"{"leaked":true}"#)
        }
        try foreign.start()

        refusal = GatewayRefusal(settle: 0, account: account)
        gateway = GatewayServer(
            port: 0,
            refusal: refusal,
            upstream: URL(string: "http://127.0.0.1:\(upstream.port)")!,
            accountReader: { [weak self] in self?.account },
            sessionsReader: { [weak self] in
                guard let bound = self?.gateway?.boundPort else { return nil }
                return [
                    Session(pid: 4242, elapsed: "01:00", isInteractive: true,
                            route: .pointedAt("http://127.0.0.1:\(bound)")),
                    Session(pid: 777, elapsed: "01:00", isInteractive: true,
                            route: .pointedAt("http://127.0.0.1:1")),
                    Session(pid: 8888, elapsed: "01:00", isInteractive: false,
                            route: .pointedAt("http://127.0.0.1:\(GatewayEndToEndTests.retiredPort)")),
                ]
            },
            portsTheAppWouldTakeDown: { [GatewayEndToEndTests.retiredPort] }
        )
        gateway.watchInterval = 0.05
        try gateway.start()
    }

    override func tearDown() {
        gateway?.stop()
        upstream?.stop()
        foreign?.stop()
        super.tearDown()
    }

    private var port: Int { gateway.boundPort ?? 0 }

    private func ask(session: String, token: String = "one") -> Int {
        var request = URLRequest(url: URL(string:
            "http://127.0.0.1:\(port)/v1/messages")!)
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

    private func control(path: String, host: String) throws -> String {
        try RawHTTPClient.send([
            "GET \(path) HTTP/1.1",
            "Host: \(host)",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n"), toPort: port)
    }

    func testAControlPathIsRefusedWhenTheHostIsNotTheLoopbackNameItListensOn() throws {
        for path in [GatewayPaths.control, GatewayPaths.sessionsAtRisk] {
            let answer = try control(path: path, host: "hats.attacker.test:\(port)")

            XCTAssertTrue(answer.hasPrefix("HTTP/1.1 403"),
                          "a page that resolved its own name to 127.0.0.1 reaches this socket like "
                              + "any local client, and only the Host header tells them apart; "
                              + "\(path) answered " + String(answer.prefix(40)))
            XCTAssertFalse(answer.contains("sessions_seen"), "and it publishes nothing")
            XCTAssertFalse(answer.contains("the account was switched"),
                           "the refusal body belongs to the post-switch 401, which tells a session "
                               + "to re-read its credential. Sending it for a denied control path "
                               + "tells the caller an account switch happened when none did")
            XCTAssertTrue(answer.contains("answers only the loopback host"),
                          "and it says what actually happened; got " + String(answer.suffix(120)))
        }
    }

    func testTheSameControlPathsStillAnswerTheLoopbackNameAndPortTheyListenOn() throws {
        for host in ["127.0.0.1:\(port)", "localhost:\(port)"] {
            XCTAssertTrue(try control(path: GatewayPaths.control, host: host)
                .hasPrefix("HTTP/1.1 200"), "the legitimate caller must keep working, host \(host)")
        }
    }

    func testTheEndpointTheBuildScriptDrivesDoesNotForkPsPerRequest() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/GatewayServer.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        XCTAssertTrue(text.contains("sessionsReader: @escaping () -> [Session]? = "
            + "{ SessionDiscovery.everySessionSeenRecently() }"),
            "sessions-at-risk is the one sweep caller anything that can reach the port may drive, "
                + "and it was the one caller still taking the uncached double-ps sweep while every "
                + "UI caller was moved to the one-second memory. A second of staleness cannot "
                + "matter to a question answered before a kill that happens later")
    }

    func testTheSessionsAtRiskPathIsAnsweredHereAndNeverForwarded() throws {
        let raw = [
            "GET \(GatewayPaths.sessionsAtRisk) HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")

        let answer = try RawHTTPClient.send(raw, toPort: port)

        XCTAssertTrue(answer.hasPrefix("HTTP/1.1 200"), String(answer.prefix(60)))
        XCTAssertTrue(answer.contains("text/plain"),
                      "the build script reads this by line, so it must not arrive as JSON")
        XCTAssertTrue(answer.hasSuffix("readable 1\npid 4242\npid 8888\n"),
                      "the session on the bound port and the one on the retired port must both be "
                      + "named, and a batch session counts; got: " + String(answer.suffix(60)))
        XCTAssertFalse(answer.contains("pid 777"),
                       "and the session pointed at another port must not be")
        XCTAssertEqual(upstreamSeen, [],
                       "a control path must be answered locally and never relayed")
        XCTAssertEqual(foreignSeen, [])
    }

    func testAnAbsoluteRequestTargetNeverReachesTheHostItNames() throws {
        let raw = [
            "POST http://127.0.0.1:\(foreign.port)/latest/meta-data HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Authorization: Bearer one",
            "Content-Length: 2",
            "Connection: close",
            "",
            "{}",
        ].joined(separator: "\r\n")

        let answer = try RawHTTPClient.send(raw, toPort: port)

        XCTAssertTrue(answer.hasPrefix("HTTP/1.1 502"),
                      "an absolute target must be refused, got: "
                      + String(answer.prefix(40)))
        XCTAssertTrue(answer.contains("gateway:"), "and named as the gateway's own refusal")
        XCTAssertEqual(foreignSeen, [],
                       "the host the target named must see nothing")
        XCTAssertEqual(upstreamSeen, [],
                       "and neither may the upstream, for a refused target")
        XCTAssertEqual(gateway.ledger.failureCount, 0,
                       "an upstream never contacted cannot have failed; counting our own refusal "
                       + "as its failure would report the gateway as sick while it worked")
        XCTAssertEqual(gateway.ledger.refusedTargetCount, 1, "the refusal is counted as itself")
    }

    func testAnOrdinaryRequestStillReachesTheUpstreamOnTheSameWire() throws {
        let raw = [
            "POST /v1/messages HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Authorization: Bearer one",
            "Content-Length: 2",
            "Connection: close",
            "",
            "{}",
        ].joined(separator: "\r\n")

        let answer = try RawHTTPClient.send(raw, toPort: port)

        XCTAssertTrue(answer.hasPrefix("HTTP/1.1 200"), String(answer.prefix(40)))
        XCTAssertEqual(upstreamSeen, ["/v1/messages"])
    }

    func testTwoSessionsBothFollowAnAccountSwitchWrittenOnDisk() {
        XCTAssertEqual(ask(session: "S1"), 200, "before a switch both sessions forward")
        XCTAssertEqual(ask(session: "S2"), 200)

        account = "claude@x.co"
        let noticed = expectation(description: "the watcher notices the account change")
        DispatchQueue.global().async { [self] in
            while refusal.snapshot().switchedTo != "claude@x.co" {
                Thread.sleep(forTimeInterval: 0.02)
            }
            noticed.fulfill()
        }
        wait(for: [noticed], timeout: 5)

        XCTAssertEqual(ask(session: "S1"), 401, "each session is refused once")
        XCTAssertEqual(ask(session: "S1", token: "minted"), 200,
                       "and its retry, carrying the token the refusal made it mint, passes")
        XCTAssertEqual(ask(session: "S2"), 401, "the second session moves too")
        XCTAssertEqual(ask(session: "S2", token: "minted"), 200)

        let after = refusal.snapshot()
        XCTAssertEqual(after.sessionsMoved, 2)
        XCTAssertEqual(after.refusals, 2)
    }

    func testAnUnreadableAccountDuringAWatchTickChangesNothing() {
        XCTAssertEqual(ask(session: "S1"), 200)
        let before = refusal.snapshot().refusals

        account = ""
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(ask(session: "S1"), 200,
                       "a tick that cannot read the account must not arm a refusal")
        XCTAssertEqual(refusal.snapshot().refusals, before)
    }

    private final class Arrivals: @unchecked Sendable {
        private let stamps = Locked<[Date]>([])

        @discardableResult
        func record() -> Int {
            stamps.mutate { $0.append(Date()); return $0.count - 1 }
        }

        var count: Int { stamps.value.count }

        var gap: TimeInterval? {
            let seen = stamps.value
            guard seen.count >= 2 else { return nil }
            return seen[1].timeIntervalSince(seen[0])
        }
    }

    private func keepAliveRequest(path: String) -> String {
        [
            "POST \(path) HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Authorization: Bearer one",
            "Content-Length: 2",
            "",
            "{}",
        ].joined(separator: "\r\n")
    }

    func testASecondPipelinedRequestWaitsForTheFirstToBeAnswered() throws {
        let stall: TimeInterval = 0.6
        let arrivals = Arrivals()
        upstream.onRequest = { _ in
            arrivals.record() == 0
                ? .stalled(seconds: stall)
                : .fixed(status: 200, headers: [:], body: #"{"echo":"ok"}"#)
        }

        let client = try RawHTTPClient.Connection(port: port)
        defer { client.hangUp() }
        try client.send(keepAliveRequest(path: "/v1/messages")
            + keepAliveRequest(path: "/v1/models"))

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, arrivals.count < 2 {
            Thread.sleep(forTimeInterval: 0.02)
        }

        XCTAssertEqual(arrivals.count, 2, "both pipelined requests must reach the upstream")
        let gap = try XCTUnwrap(arrivals.gap)
        XCTAssertGreaterThan(
            gap, stall / 2,
            "the second request must not be started while the first relay is still in flight, "
                + "or one handler holds two relays and a disconnect cancels only the later one; "
                + "measured gap \(gap)s against a \(stall)s stall"
        )
    }

    func testABodyLargerThanTheGatewayAcceptsIsRefusedByItsDeclaredLength() throws {
        gateway.maxBodyBytes = 1024
        let raw = [
            "POST /v1/messages HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Authorization: Bearer one",
            "Content-Length: 1048576",
            "",
            "",
        ].joined(separator: "\r\n")

        let answer = try RawHTTPClient.send(raw, toPort: port)

        XCTAssertTrue(answer.hasPrefix("HTTP/1.1 413"),
                      "a declared length over the limit is refused before a byte is read, got: "
                          + String(answer.prefix(40)))
        XCTAssertEqual(upstreamSeen, [], "and nothing is forwarded")
    }

    func testAChunkedBodyIsRefusedOnceItGrowsPastTheLimit() throws {
        gateway.maxBodyBytes = 1024
        let chunk = String(repeating: "x", count: 512)
        var raw = [
            "POST /v1/messages HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Authorization: Bearer one",
            "Transfer-Encoding: chunked",
            "",
            "",
        ].joined(separator: "\r\n")
        for _ in 0..<8 {
            raw += "200\r\n" + chunk + "\r\n"
        }
        raw += "0\r\n\r\n"

        let answer = try RawHTTPClient.send(raw, toPort: port)

        XCTAssertTrue(answer.hasPrefix("HTTP/1.1 413"),
                      "a body that declares no length is weighed as it arrives, got: "
                          + String(answer.prefix(40)))
        XCTAssertEqual(upstreamSeen, [],
                       "a request refused for its size must never reach the upstream")
    }

    func testABodyWithinTheLimitStillReachesTheUpstream() throws {
        gateway.maxBodyBytes = 1024
        let body = String(repeating: "x", count: 512)
        let raw = [
            "POST /v1/messages HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Authorization: Bearer one",
            "Content-Length: \(body.utf8.count)",
            "Connection: close",
            "",
            body,
        ].joined(separator: "\r\n")

        let answer = try RawHTTPClient.send(raw, toPort: port)

        XCTAssertTrue(answer.hasPrefix("HTTP/1.1 200"), String(answer.prefix(40)))
        XCTAssertEqual(upstreamSeen, ["/v1/messages"], "the guard must not refuse what fits")
    }

    func testARefusedBodyEndsTheConnectionInsteadOfWedgingIt() throws {
        gateway.maxBodyBytes = 1024
        let client = try RawHTTPClient.Connection(port: port)
        defer { client.hangUp() }

        try client.send([
            "POST /v1/messages HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Authorization: Bearer one",
            "Content-Length: 1048576",
            "",
            "",
        ].joined(separator: "\r\n"))
        try client.waitUntilTheBodyStarts()

        XCTAssertTrue(client.received.hasPrefix("HTTP/1.1 413"), String(client.received.prefix(40)))
        XCTAssertTrue(client.received.lowercased().contains("connection: close"),
                      "the client is told the wire is done with")
        try client.waitUntilTheServerHangsUp()
        XCTAssertEqual(upstreamSeen, [], "and nothing was forwarded")
    }

    func testAConnectionNobodyHangsUpStillClosesItsSocket() throws {
        let before = upstream.disconnects
        try autoreleasepool {
            let client = try RawHTTPClient.Connection(port: upstream.port)
            try client.send("GET /x HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
            try client.waitUntilTheBodyStarts()
        }

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, upstream.disconnects == before {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertEqual(upstream.disconnects, before + 1,
                       "a helper that leaves the wire open when nobody hangs up leaves its event loop "
                           + "running too, and a test that throws before its hang-up leaks both")
    }

    func testAnUpstreamThatStopsAnsweringMidStreamIsNotSignedOffAsComplete() throws {
        gateway.upstreamTimeout = 0.5
        upstream.onRequest = { _ in .stallsAfter(chunks: ["data: one\n\n"]) }
        let client = try RawHTTPClient.Connection(port: port)
        defer { client.hangUp() }

        try client.send([
            "POST /v1/messages HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Authorization: Bearer one",
            "Content-Length: 2",
            "",
            "{}",
        ].joined(separator: "\r\n"))
        try client.waitUntilTheServerHangsUp()

        XCTAssertTrue(client.received.contains("data: one"), "what did arrive is still relayed")
        XCTAssertFalse(client.received.hasSuffix("0\r\n\r\n"),
                       "a stream the upstream abandoned must not be terminated on its behalf; the "
                           + "client has to see a truncated message rather than a clean end it would "
                           + "mistake for the whole answer")
        XCTAssertEqual(gateway.ledger.failureCount, 1,
                       "and the head's 200 must not stay the last word on a request that failed")
    }

    func testTheStatusPathReportsWhatPassedThroughWithoutNamingAToken() {
        _ = ask(session: "S1", token: "sk-secret-value")

        var body = ""
        let waiter = expectation(description: "status")
        URLSession.shared.dataTask(with: URL(string:
            "http://127.0.0.1:\(port)\(GatewayPaths.control)")!) { data, _, _ in
            body = String(data: data ?? Data(), encoding: .utf8) ?? ""
            waiter.fulfill()
        }.resume()
        wait(for: [waiter], timeout: 15)

        XCTAssertTrue(body.contains("\"requests\""), body)
        XCTAssertFalse(body.contains("sk-secret-value"), "a token must never be reported")
        XCTAssertEqual(upstreamSeen, ["/v1/messages"], "status is answered locally")
    }
}
