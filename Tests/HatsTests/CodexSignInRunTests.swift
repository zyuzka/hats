import Darwin
import XCTest
@testable import Hats

final class CodexSignInRunTests: XCTestCase {
    private var opened: [URL] = []
    private var endings: [CodexSignInRun.Ending] = []
    private var deadlines: [() -> Void] = []
    private var exchanged: [URLRequest] = []
    private var answer: (status: Int, body: Data?) = (0, nil)

    private func run(ports: [Int]) -> CodexSignInRun {
        let run = CodexSignInRun(world: CodexSignInWorld(
            ports: ports,
            random: { Data(repeating: 1, count: $0) },
            now: { CodexFixture.now },
            open: { [unowned self] in self.opened.append($0) },
            send: { [unowned self] in
                self.exchanged.append($0)
                return self.answer
            },
            after: { [unowned self] _, work in self.deadlines.append(work) },
            onMain: { $0() }
        ))
        run.ended = { [unowned self] in self.endings.append($0) }

        return run
    }

    private func state(of url: URL?) throws -> String {
        let items = try XCTUnwrap(URLComponents(url: try XCTUnwrap(url), resolvingAgainstBaseURL: false)?.queryItems)
        return try XCTUnwrap(items.first { $0.name == "state" }?.value)
    }

    func testABusyFirstPortMovesToTheSecondWithoutAskingTheOtherToCancel() throws {
        let ports = LocalSockets.freePorts(2)
        var heard: [String] = []
        let lock = NSLock()
        let blocker = try CodexCallbackListener.open(ports: [ports[0]]) { target in
            lock.lock()
            heard.append(target)
            lock.unlock()
            return .plain(404, "Not Found")
        }
        defer { blocker.close() }
        let signIn = run(ports: ports)

        try signIn.start()
        defer { signIn.cancel() }
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertEqual(signIn.port, ports[1])
        XCTAssertTrue(try XCTUnwrap(opened.first).absoluteString.contains("127.0.0.1%3A\(ports[1])%2Fauth%2Fcallback"))
        lock.lock()
        XCTAssertEqual(heard, [], "no GET /cancel: a codex login of the person may be waiting there")
        lock.unlock()
    }

    func testBothPortsBusyIsAMessageAndNothingOpens() throws {
        let ports = LocalSockets.freePorts(2)
        let first = try CodexCallbackListener.open(ports: [ports[0]]) { _ in .plain(404, "") }
        let second = try CodexCallbackListener.open(ports: [ports[1]]) { _ in .plain(404, "") }
        defer {
            first.close()
            second.close()
        }

        XCTAssertThrowsError(try run(ports: ports).start()) {
            XCTAssertEqual($0 as? CodexError, .portsTaken(ports))
        }
        XCTAssertEqual(opened, [])
    }

    func testAForeignStateIsRefusedAndTheRightOneSignsIn() throws {
        let port = LocalSockets.freePorts(1)[0]
        let signIn = run(ports: [port])
        let tokens: [String: String] = [
            "id_token": CodexFixture.idToken(user: "u", account: "a", email: "work@example.com"),
            "access_token": CodexFixture.accessToken(expiresAt: CodexFixture.now, tag: "a"),
            "refresh_token": "r-1",
        ]
        answer = (200, try JSONSerialization.data(withJSONObject: tokens))
        try signIn.start()
        let state = try state(of: opened.first)

        let foreign = try LocalSockets.get("/auth/callback?code=c&state=someone-else", port: port)
        XCTAssertTrue(foreign.hasPrefix("HTTP/1.1 400"))
        XCTAssertEqual(endings, [], "the wait goes on")
        XCTAssertTrue(signIn.isInFlight)

        let right = try LocalSockets.get("/auth/callback?code=the-code&state=\(state)", port: port)
        XCTAssertTrue(right.hasPrefix("HTTP/1.1 302"))
        XCTAssertTrue(right.contains("Location: /success\r\n"), "no token goes into the address")
        let success = try LocalSockets.get("/success", port: port)
        XCTAssertTrue(success.hasPrefix("HTTP/1.1 200"))
        XCTAssertFalse(success.contains("id_token"))

        guard case .signedIn(let data)? = endings.first else { return XCTFail("\(endings)") }
        XCTAssertEqual(CodexAuth(data: data)?.refreshToken, "r-1")
        XCTAssertEqual(CodexAuth(data: data)?.owner, CodexOwner(userID: "u", accountID: "a"))
        XCTAssertTrue(String(data: exchanged.first?.httpBody ?? Data(), encoding: .utf8)?.contains("code=the-code") ?? false)
        deadlines.forEach { $0() }
        XCTAssertEqual(endings.count, 1, "the deadline after the end changes nothing")
    }

    func testARefusalOfThePageEndsAndClosesTheListener() throws {
        let port = LocalSockets.freePorts(1)[0]
        let signIn = run(ports: [port])
        try signIn.start()
        let state = try state(of: opened.first)

        _ = try LocalSockets.get("/auth/callback?state=\(state)&error=access_denied", port: port)

        XCTAssertEqual(endings, [.refused("The sign-in page refused: access_denied.")])
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertThrowsError(try LocalSockets.get("/auth/callback", port: port), "nobody listens any more")
    }

    func testCancelAndTheDeadlineEachEndTheWaitWithNothingStored() throws {
        let cancelled = run(ports: [LocalSockets.freePorts(1)[0]])
        try cancelled.start()
        cancelled.cancel()
        XCTAssertEqual(endings, [.cancelled])

        endings = []
        deadlines = []
        let forgotten = run(ports: [LocalSockets.freePorts(1)[0]])
        try forgotten.start()
        XCTAssertEqual(deadlines.count, 1)
        deadlines.forEach { $0() }
        XCTAssertEqual(endings, [.timedOut])
        XCTAssertEqual(exchanged, [])
    }

    func testTheWaitIsFifteenMinutes() {
        XCTAssertEqual(CodexOAuth.waitLimit, 15 * 60)
    }
}
