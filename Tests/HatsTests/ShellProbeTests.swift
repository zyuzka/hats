import XCTest
@testable import Hats

final class ShellProbeTests: XCTestCase {
    private static let unset = "UNSET"

    private func sourcing(
        _ block: String,
        shell: String = "/bin/zsh",
        arguments: [String] = ["-f"],
        adding extras: [String: String] = [:],
        reading name: String = ShellEnvironment.baseURLName
    ) throws -> String {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-probe-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: file) }
        try (block + "\nprintf '%s' \"${\(name):-\(Self.unset)}\"\n")
            .write(to: file, atomically: true, encoding: .utf8)

        var environment = ProcessInfo.processInfo.environment
        for stripped in [ShellEnvironment.baseURLName,
                         "_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL",
                         "CLAUDE_GATEWAY_ALLOW_LOOPBACK"] {
            environment.removeValue(forKey: stripped)
        }
        environment.merge(extras) { _, new in new }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = arguments + [file.path]
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func exported(from block: String, adding extras: [String: String] = [:]) throws -> String {
        try sourcing(block, adding: extras)
    }

    private func listener(_ answer: @escaping (NIOTestListener.Request) -> NIOTestListener.Answer) throws
        -> NIOTestListener {
        let made = NIOTestListener()
        made.onRequest = answer
        try made.start()
        return made
    }

    private func block(for port: Int, dialect: ShellDialect = .posix) -> String {
        ShellEnvironment.block(baseURL: "http://127.0.0.1:\(port)", dialect: dialect)
    }

    func testOnlyOurOwnGatewayMakesTheBlockExport() throws {
        let ours = GatewayServer(port: 0, refusal: nil)
        try ours.start()
        defer { ours.stop() }
        let port = try XCTUnwrap(ours.boundPort)
        XCTAssertEqual(try exported(from: block(for: port)), "http://127.0.0.1:\(port)",
                       "the gateway answers its control path with its own marker in the body")
    }

    func testEveryWayAStrangerCanAnswerIsRefused() throws {
        let notFound = try listener { _ in .fixed(status: 404, headers: [:], body: "not found") }
        defer { notFound.stop() }
        XCTAssertEqual(try exported(from: block(for: notFound.port)), Self.unset,
                       "python3 -m http.server: 200 on / and 404 on the control path")

        let redirect = try listener {
            _ in .fixed(status: 302, headers: ["Location": "http://example.invalid/"], body: "")
        }
        defer { redirect.stop() }
        XCTAssertEqual(try exported(from: block(for: redirect.port)), Self.unset,
                       "curl -sf exits 0 on a 3xx — measured on curl 8.7.1 — so -f alone is not a guard")

        let catchAll = try listener { _ in .fixed(status: 200, headers: [:], body: "<html>hello</html>") }
        defer { catchAll.stop() }
        XCTAssertEqual(try exported(from: block(for: catchAll.port)), Self.unset,
                       "a stranger answering 200 to every path is the case a status-code check misses")

        let impostor = try listener { _ in .fixed(status: 204, headers: [:], body: "") }
        defer { impostor.stop() }
        XCTAssertEqual(try exported(from: block(for: impostor.port)), Self.unset,
                       "a 2xx that is not 200 carries no body either")
    }

    func testAProxyInTheEnvironmentCannotAnswerForTheGateway() throws {
        let cached = #"{"served_by" : "\#(GatewayPaths.marker)", "requests" : 1}"#
        let proxy = try listener { _ in .fixed(status: 200, headers: [:], body: cached) }
        defer { proxy.stop() }
        let vacated = NIOTestListener()
        try vacated.start()
        let deadPort = vacated.port
        vacated.stop()

        let viaProxy = ["http_proxy": "http://127.0.0.1:\(proxy.port)",
                        "all_proxy": "http://127.0.0.1:\(proxy.port)"]
        XCTAssertEqual(try exported(from: block(for: deadPort), adding: viaProxy), Self.unset,
                       "curl honours http_proxy even for a loopback URL — measured. A proxy holding "
                           + "a cached copy of our own status answers with our own marker, so the "
                           + "body check alone cannot save this: the request must never leave")
    }

    func testWithTheAppGoneNothingIsExported() throws {
        let vacated = NIOTestListener()
        try vacated.start()
        let deadPort = vacated.port
        vacated.stop()
        XCTAssertEqual(try exported(from: block(for: deadPort)), Self.unset,
                       "the block is litter, not a lie: claude runs directly, no uninstall step needed")
    }

    func testAllThreeVariablesCrossTheGuardTogether() throws {
        let ours = GatewayServer(port: 0, refusal: nil)
        try ours.start()
        defer { ours.stop() }
        let port = try XCTUnwrap(ours.boundPort)

        for name in [ShellEnvironment.baseURLName,
                     "_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL",
                     "CLAUDE_GATEWAY_ALLOW_LOOPBACK"] {
            XCTAssertNotEqual(try sourcing(block(for: port), reading: name), Self.unset,
                              "\(name) is inside the same conditional and must be exported with the rest")
        }

        let vacated = NIOTestListener()
        try vacated.start()
        let deadPort = vacated.port
        vacated.stop()
        for name in ["_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL", "CLAUDE_GATEWAY_ALLOW_LOOPBACK"] {
            XCTAssertEqual(try sourcing(block(for: deadPort), reading: name), Self.unset,
                           "\(name) must not escape the guard either")
        }
    }

    func testTheCshBlockIsRunByCshAndNotOnlyParsedByIt() throws {
        let csh = "/bin/tcsh"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: csh))
        let ours = GatewayServer(port: 0, refusal: nil)
        try ours.start()
        defer { ours.stop() }
        let port = try XCTUnwrap(ours.boundPort)

        let script = block(for: port, dialect: .csh) + "\nprintenv \(ShellEnvironment.baseURLName)\n"
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-probe-\(UUID().uuidString).csh")
        defer { try? FileManager.default.removeItem(at: file) }
        try script.write(to: file, atomically: true, encoding: .utf8)

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: ShellEnvironment.baseURLName)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: csh)
        process.arguments = ["-f", file.path]
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let seen = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        XCTAssertEqual(seen.trimmingCharacters(in: .whitespacesAndNewlines),
                       "http://127.0.0.1:\(port)",
                       "the csh conditional was only ever syntax-checked; this runs it")
    }

    func testTheProbeIsBoundedByItsOwnTimeoutAndNotByAGenerousGuess() throws {
        let stalling = try listener { _ in .stalled(seconds: 30) }
        defer { stalling.stop() }
        let started = Date()
        XCTAssertEqual(try exported(from: block(for: stalling.port)), Self.unset)
        let spent = Date().timeIntervalSince(started)
        XCTAssertLessThan(spent, Double(ShellEnvironment.probeTimeoutSeconds) + 1.5,
                          "a server that accepts and never answers must cost one shell start "
                              + "\(ShellEnvironment.probeTimeoutSeconds) s, not a hang")
    }
}
