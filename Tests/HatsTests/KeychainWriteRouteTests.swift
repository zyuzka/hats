import XCTest
@testable import Hats

final class KeychainWriteRouteTests: XCTestCase {
    func testHatsOwnItemsGoThroughTheSecurityAPI() {
        for service in [Slot.parked("A-1"), Slot.legacyParked("A-1"), Slot.codexParked("C-1")] {
            XCTAssertEqual(Keychain.route(for: service), .hatsOwned, service)
        }
    }

    func testClaudeCodeLiveItemsGoThroughSecurityInteractive() {
        let services = [
            CLIState.credentialService(environment: [:]),
            CLIState.credentialService(environment: [CLIState.configDirVariable: "/tmp/alt"]),
        ]
        for service in services {
            XCTAssertEqual(Keychain.route(for: service), .claudeCodeLive, service)
        }
    }

    func testEachRouteWritesOnlyThroughItsOwnPath() throws {
        let owned = [Slot.parked("A-1"), Slot.legacyParked("A-1"), Slot.codexParked("C-1")]
        let live = [
            CLIState.credentialService(environment: [:]),
            CLIState.credentialService(environment: [CLIState.configDirVariable: "/tmp/alt"]),
        ]
        var calls: [String] = []

        for service in owned + live {
            try Keychain.write(
                service: service,
                account: "me",
                data: Data("x".utf8),
                own: { name, _, _ in calls.append("own \(name)") },
                live: { name, _, _ in calls.append("live \(name)") }
            )
        }

        XCTAssertEqual(calls, owned.map { "own \($0)" } + live.map { "live \($0)" })
    }

    func testTheLiveItemIsReadBySecurityWithoutTheAPI() throws {
        var askedAPI = false
        var finds = 0

        let value = try Keychain.read(
            service: CLIState.credentialService(environment: [:]),
            account: "me",
            readOwn: { _, _ in
                askedAPI = true
                return .found(Data("api".utf8))
            },
            find: { _ in
                finds += 1
                return Keychain.Result(status: 0, stdout: "live", stderr: "")
            }
        )

        XCTAssertEqual(value, Data("live".utf8))
        XCTAssertFalse(askedAPI, "the live Claude Code item must not be read through the Security API")
        XCTAssertEqual(finds, 1)
    }

    func testRunHandsTheInputToTheProcessAndClosesIt() {
        let input = Data(String(repeating: "abc", count: 1344).utf8)
        var result: Keychain.Result?
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            result = Keychain.run([], input: input, executable: "/bin/cat")
            done.signal()
        }

        let finished = done.wait(timeout: .now() + 10) == .success

        XCTAssertTrue(finished, "run did not return in 10 s: stdin was not closed, so the process waits for more")
        XCTAssertEqual(result?.status, 0)
        XCTAssertEqual(result.map { Data($0.stdout.utf8) }, input)
    }

    func testTheCommandCarriesTheValueAsHexAndEndsWithANewline() throws {
        let command = try Keychain.createInteractiveAddCommand(
            service: "Claude Code-credentials",
            account: "me",
            data: Data("{\"a\":1}".utf8)
        )

        XCTAssertEqual(
            command,
            "add-generic-password -U -a \"me\" -s \"Claude Code-credentials\" -X \"7b2261223a317d\"\n"
        )
    }

    func testTheCommandAtTheLimitIsAccepted() throws {
        let fixed = "add-generic-password -U -a \"me\" -s \"ST\" -X \"\"\n".utf8.count
        let bytes = (Keychain.interactiveCommandLimit - fixed) / 2
        let command = try Keychain.createInteractiveAddCommand(
            service: "ST",
            account: "me",
            data: Data(repeating: 0x41, count: bytes)
        )

        XCTAssertEqual(command.utf8.count, Keychain.interactiveCommandLimit)
    }

    func testAValueOverTheLimitIsRefusedAndNothingRuns() {
        let fixed = "add-generic-password -U -a \"me\" -s \"ST\" -X \"\"\n".utf8.count
        let bytes = (Keychain.interactiveCommandLimit - fixed) / 2 + 1
        var ran = false

        XCTAssertThrowsError(try Keychain.writeLiveItem(
            service: "ST",
            account: "me",
            data: Data(repeating: 0x41, count: bytes),
            runInteractive: { _ in
                ran = true
                return Keychain.Result(status: 0, stdout: "", stderr: "")
            }
        ))
        XCTAssertFalse(ran, "an oversized value must not reach security at all, so nothing is cut")
    }

    func testTheValueReachesSecurityOnStdinOnly() throws {
        var sent = Data()
        try Keychain.writeLiveItem(
            service: "S",
            account: "me",
            data: Data("secret".utf8),
            runInteractive: { input in
                sent = input
                return Keychain.Result(status: 0, stdout: "", stderr: "")
            }
        )

        XCTAssertEqual(
            String(data: sent, encoding: .utf8),
            "add-generic-password -U -a \"me\" -s \"S\" -X \"736563726574\"\n"
        )
    }

    func testAFailedInteractiveWriteThrows() {
        XCTAssertThrowsError(try Keychain.writeLiveItem(
            service: "S",
            account: "me",
            data: Data("x".utf8),
            runInteractive: { _ in Keychain.Result(status: 1, stdout: "", stderr: "boom") }
        ))
    }

    func testANameThatCannotBeQuotedIsRefused() {
        for (service, account) in [("S\"", "me"), ("S", "m\\e"), ("S\n", "me")] {
            XCTAssertThrowsError(try Keychain.createInteractiveAddCommand(
                service: service,
                account: account,
                data: Data("x".utf8)
            ), "\(service) / \(account)")
        }
    }

    func testNoArgumentListInTheKeychainSourcesCarriesTheValue() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats")
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasPrefix("Keychain") && $0.hasSuffix(".swift") }
        XCTAssertTrue(files.contains("Keychain+Route.swift"), "the scan sees every Keychain file: \(files)")
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("\"-w\", value"), "\(file) passes the value with -w in argv")
            XCTAssertFalse(text.contains("\"-X\", "), "\(file) passes the value with -X in argv")
        }
    }
}
