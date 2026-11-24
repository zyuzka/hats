import NIOCore
import NIOPosix
import XCTest
@testable import Hats

final class CodexServiceClientTests: XCTestCase {
    private let thread = "01a1f45d-1f8b-70d2-9802-e99966ada0d2"
    private var service: FakeCodexService!
    private var group: MultiThreadedEventLoopGroup!

    override func setUpWithError() throws {
        try super.setUpWithError()
        service = FakeCodexService()
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    override func tearDown() {
        service.stop()
        try? group.syncShutdownGracefully()
        super.tearDown()
    }

    private func connect() throws -> CodexServiceClient {
        try CodexServiceClient.connect(path: service.path, group: group, within: .seconds(3))
    }

    func testConnectingSaysHelloWithoutTheExperimentalApiAndSaysInitialized() throws {
        try service.start()
        let client = try connect()
        defer { client.close() }
        _ = try client.call("thread/loaded/list", [:], within: .seconds(3))
        let methods = service.received.map(\.method)
        XCTAssertEqual(methods, ["initialize", "initialized", "thread/loaded/list"])
        let capabilities = service.received[0].params["capabilities"] as? [String: Any]
        XCTAssertEqual(capabilities?["experimentalApi"] as? Bool, false)
        let info = service.received[0].params["clientInfo"] as? [String: Any]
        XCTAssertEqual(info?["name"] as? String, "hats")
    }

    func testAThreadReadComesBackAsTheThreadState() throws {
        try service.start()
        service.onCall = { [thread] call in
            call.method == "thread/read" ? (.result(FakeCodexService.thread(thread, status: "idle")), []) : (.result([:]), [])
        }
        let session = CodexServiceSession(client: try connect())
        defer { session.close() }
        let state = try session.read(thread)
        XCTAssertEqual(state, CodexThreadState(status: "idle", isEphemeral: false, hasPath: true, isRoot: true))
        XCTAssertEqual(service.received.last?.params["threadId"] as? String, thread)
    }

    func testRereadingTheLoginAsksForARefreshAndReturnsTheAccountEmail() throws {
        try service.start()
        service.onCall = { call in
            guard call.method == "account/read" else { return (.result([:]), []) }
            return (.result(["account": ["type": "chatgpt", "email": "work@example.com"]]), [])
        }
        let session = CodexServiceSession(client: try connect())
        defer { session.close() }
        let account = try session.findAccountAfterRereadingLogin()
        XCTAssertEqual(account, "work@example.com")
        XCTAssertEqual(service.received.last?.method, "account/read")
        XCTAssertEqual(service.received.last?.params["refreshToken"] as? Bool, true)
    }

    func testAnErrorAnswerIsARefusalWithItsCodeAndMessage() throws {
        try service.start()
        service.onCall = { call in
            call.method == "thread/read" ? (.error(code: -32600, message: "thread not found"), []) : (.result([:]), [])
        }
        let client = try connect()
        defer { client.close() }
        XCTAssertThrowsError(try client.call("thread/read", ["threadId": thread], within: .seconds(3))) {
            XCTAssertEqual($0 as? CodexServiceError, .refused(code: -32600, message: "thread not found"))
        }
    }

    func testCompactionWaitsForTheIdleStatusOfItsOwnThread() throws {
        try service.start()
        service.onCall = { [thread] call in
            guard call.method == "thread/compact/start" else { return (.result([:]), []) }
            return (.result([:]), [
                FakeCodexService.status(thread, "active"),
                FakeCodexService.status("another-thread", "idle"),
                FakeCodexService.status(thread, "idle"),
            ])
        }
        let session = CodexServiceSession(client: try connect())
        defer { session.close() }
        XCTAssertEqual(try session.compact(thread, within: 3), .idle)
    }

    func testCompactionWithoutIdleInTimeIsFalse() throws {
        try service.start()
        service.onCall = { [thread] call in
            call.method == "thread/compact/start"
                ? (.result([:]), [FakeCodexService.status(thread, "active")])
                : (.result([:]), [])
        }
        let session = CodexServiceSession(client: try connect())
        defer { session.close() }
        XCTAssertEqual(try session.compact(thread, within: 1), .timedOut)
    }

    func testAnIdleBeforeTheCompactionWentActiveDoesNotEndTheWait() throws {
        try service.start()
        service.onCall = { [thread] call in
            call.method == "thread/compact/start"
                ? (.result([:]), [FakeCodexService.status(thread, "idle")])
                : (.result([:]), [])
        }
        let session = CodexServiceSession(client: try connect())
        defer { session.close() }
        XCTAssertEqual(try session.compact(thread, within: 1), .timedOut)
    }

    func testAConnectionLostDuringTheCompactionIsLostNotRefused() throws {
        try service.start()
        service.onCall = { [thread] call in
            call.method == "thread/compact/start"
                ? (.result([:]), [FakeCodexService.status(thread, "active")])
                : (.result([:]), [])
        }
        let client = try connect()
        let session = CodexServiceSession(client: client)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { client.close() }
        XCTAssertEqual(try session.compact(thread, within: 3), .lost(.closed))
    }

    func testARequestFromTheServiceIsReportedAndNotAnswered() throws {
        try service.start()
        let methods = Locked<[String]>([])
        service.onCall = { call in
            call.method == "thread/loaded/list"
                ? (.result([:]), [["id": 900, "method": "item/commandExecution/requestApproval", "params": [:]]])
                : (.result([:]), [])
        }
        let client = try CodexServiceClient.connect(path: service.path, group: group, within: .seconds(3)) { method in
            methods.mutate { $0.append(method) }
        }
        defer { client.close() }
        _ = try client.call("thread/loaded/list", [:], within: .seconds(3))
        let deadline = Date().addingTimeInterval(2)
        while methods.value.isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertEqual(methods.value, ["item/commandExecution/requestApproval"])
        XCTAssertEqual(service.received.map(\.method), ["initialize", "initialized", "thread/loaded/list"])
    }

    func testAnAnswerInTwoFramesIsPutTogether() throws {
        try service.start()
        service.onCall = { [thread] call in
            call.method == "thread/read" ? (.fragmented(FakeCodexService.thread(thread, status: "active")), []) : (.result([:]), [])
        }
        let session = CodexServiceSession(client: try connect())
        defer { session.close() }
        XCTAssertEqual(try session.read(thread).status, "active")
    }

    func testAPingIsAnsweredWithAPong() throws {
        try service.start()
        let client = try connect()
        defer { client.close() }
        service.ping("are you there")
        let deadline = Date().addingTimeInterval(2)
        while service.pongsReceived.isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertEqual(service.pongsReceived, ["are you there"])
    }

    func testATurnCarriesTheTextAsOneTextInput() throws {
        try service.start()
        let session = CodexServiceSession(client: try connect())
        defer { session.close() }
        try session.startTurn(thread, text: CodexContinueSteps.text)
        let call = try XCTUnwrap(service.received.last)
        XCTAssertEqual(call.method, "turn/start")
        XCTAssertEqual(call.params["threadId"] as? String, thread)
        let input = call.params["input"] as? [[String: Any]]
        XCTAssertEqual(input?.count, 1)
        XCTAssertEqual(input?.first?["type"] as? String, "text")
        XCTAssertEqual(input?.first?["text"] as? String, CodexContinueSteps.text)
    }

    func testAnUnansweredCallTimesOut() throws {
        try service.start()
        service.onCall = { call in call.method == "thread/read" ? (.silence, []) : (.result([:]), []) }
        let client = try connect()
        defer { client.close() }
        XCTAssertThrowsError(try client.call("thread/read", [:], within: .milliseconds(300))) {
            XCTAssertEqual($0 as? CodexServiceError, .timedOut("thread/read"))
        }
    }

    func testNoSocketIsNoService() {
        XCTAssertThrowsError(try connect()) {
            XCTAssertEqual(($0 as? CodexServiceError)?.reason, "noService")
        }
    }

    func testARefusedUpgradeIsAHandshakeFailure() throws {
        try service.start(upgrades: false)
        XCTAssertThrowsError(try connect()) {
            XCTAssertEqual($0 as? CodexServiceError, .handshake("status 403"))
        }
    }
}
