import XCTest
@testable import Hats

final class CodexSignInLateTests: XCTestCase {
    private func run(ports: [Int], send: @escaping (URLRequest) -> (status: Int, body: Data?),
                     opened: @escaping (URL) -> Void) -> CodexSignInRun {
        CodexSignInRun(world: CodexSignInWorld(
            ports: ports,
            random: { Data(repeating: 2, count: $0) },
            now: { CodexFixture.now },
            open: opened,
            send: send,
            after: { _, _ in },
            onMain: { $0() }
        ))
    }

    func testAnExchangeThatEndsAfterTheCancelIsNotCalledSignedIn() throws {
        let port = LocalSockets.freePorts(1)[0]
        let exchanging = DispatchSemaphore(value: 0)
        let mayAnswer = DispatchSemaphore(value: 0)
        let tokens = try JSONSerialization.data(withJSONObject: [
            "id_token": CodexFixture.idToken(user: "u", account: "a", email: "work@example.com"),
            "access_token": "a",
            "refresh_token": "r",
        ])
        var url: URL?
        let signIn = run(ports: [port], send: { _ in
            exchanging.signal()
            mayAnswer.wait()
            return (200, tokens)
        }, opened: { url = $0 })
        var endings: [CodexSignInRun.Ending] = []
        let lock = NSLock()
        signIn.ended = { ending in
            lock.lock()
            endings.append(ending)
            lock.unlock()
        }
        try signIn.start()
        let state = try XCTUnwrap(URLComponents(url: try XCTUnwrap(url), resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value)
        var page = ""
        let answered = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            page = (try? LocalSockets.get("/auth/callback?code=c&state=\(state)", port: port)) ?? ""
            answered.signal()
        }

        XCTAssertEqual(exchanging.wait(timeout: .now() + 5), .success)
        signIn.cancel()
        mayAnswer.signal()
        XCTAssertEqual(answered.wait(timeout: .now() + 5), .success)

        XCTAssertFalse(page.hasPrefix("HTTP/1.1 302"), "the browser is not told it signed in")
        XCTAssertTrue(page.contains("nothing was stored"))
        lock.lock()
        XCTAssertEqual(endings, [.cancelled])
        lock.unlock()
    }

    func testOnlyTheCurrentRunClosesTheSignIn() {
        let flow = CodexSignInFlow()
        let old = run(ports: [], send: { _ in (0, nil) }, opened: { _ in })
        let new = run(ports: [], send: { _ in (0, nil) }, opened: { _ in })
        flow.track(old)
        flow.track(new)

        flow.settle(old)
        XCTAssertTrue(flow.run === new, "the run that ended earlier leaves the new one alone")

        flow.settle(new)
        XCTAssertNil(flow.run)
    }
}
