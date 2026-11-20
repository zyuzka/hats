import XCTest
@testable import Hats

final class UsageHeadersWiringTests: XCTestCase {
    private func sourceOf(_ name: String) throws -> String {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/\(name)")

        return try String(contentsOf: source, encoding: .utf8)
    }

    func testTheSinkIsSetBeforeTheGatewayStarts() throws {
        let main = try sourceOf("main.swift")
        let listen = try XCTUnwrap(main.range(of: "        listenToUsageHeaders()\n"))
        let start = try XCTUnwrap(main.range(of: "        startOrStopTheGateway()\n"))

        XCTAssertLessThan(listen.lowerBound, start.lowerBound,
                          "the server takes the sink when it is built; a gateway started first keeps nil "
                              + "and the header signal is off until the next restart")
        XCTAssertTrue(try sourceOf("AppDelegate+UsageHeaders.swift").contains("GatewayProcess.usageSink = {"),
                      "listening is what sets the sink")
    }

    func testEveryServerTheProcessBuildsIsGivenTheSink() throws {
        let process = try sourceOf("GatewayProcess.swift")
        let attempted = try XCTUnwrap(process.range(of: "private static func attempted("))
        let body = String(process[attempted.lowerBound...].prefix(400))

        XCTAssertTrue(body.contains("usageSink: usageSink\n"),
                      "usageSink: nil here switches the header signal off with every test green")
        XCTAssertEqual(process.components(separatedBy: "GatewayServer(").count - 1, 1,
                       "attempted is the only place a server is built, so the check above covers them all")
        XCTAssertTrue(try sourceOf("GatewayHandler.swift").contains("usageSink: server.usageSink"),
                      "and the server hands it on to each relay")
    }
}
