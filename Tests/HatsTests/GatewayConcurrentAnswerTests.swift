import XCTest
@testable import Hats

final class GatewayConcurrentAnswerTests: XCTestCase {
    private func request(port: Int) -> String {
        [
            "GET \(GatewayPaths.sessionsAtRisk) HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
    }

    func testAnsweringTheGuardWhileTheListenerClosesReadsTheChannelSafely() throws {
        let server = GatewayServer(
            port: 0,
            refusal: nil,
            sessionsReader: {
                [Session(pid: 4242, elapsed: "01:00", isInteractive: false,
                         route: .pointedAt("http://127.0.0.1:1"))]
            },
            portsTheAppWouldTakeDown: { [] }
        )
        try server.start()
        let port = try XCTUnwrap(server.boundPort)
        let raw = request(port: port)

        let asking = DispatchQueue(label: "hats.test.asking", attributes: .concurrent)
        let answered = DispatchSemaphore(value: 0)
        let finished = DispatchGroup()
        for _ in 0..<8 {
            asking.async(group: finished) {
                for _ in 0..<10 {
                    _ = try? RawHTTPClient.send(raw, toPort: port)
                    answered.signal()
                }
            }
        }

        XCTAssertEqual(answered.wait(timeout: .now() + 10), .success,
                       "the endpoint has to be under way before the close, or the two never meet")
        server.stop()

        XCTAssertEqual(finished.wait(timeout: .now() + 30), .success,
                       "every asker returns, whether it got an answer or a closed socket; the point "
                           + "of the check is that boundPort is read off the event loop while stop() "
                           + "clears the channel from here, which the thread sanitizer sees")
    }
}
