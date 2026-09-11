import XCTest
@testable import Hats

final class GatewayListenerLifecycleTests: XCTestCase {
    private var portBeforeTheTest = 8787

    override func setUp() {
        super.setUp()
        portBeforeTheTest = GatewayProcess.port
    }

    override func tearDown() {
        GatewayProcess.stop()
        GatewayProcess.port = portBeforeTheTest
        super.tearDown()
    }

    private func aFreePort() throws -> Int {
        let probe = NIOTestListener()
        try probe.start()
        let port = probe.port
        probe.stop()
        return port
    }

    private func answers(on port: Int) -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)\(GatewayPaths.control)")
        guard let url else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        var served = false
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            served = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 4)
        return served
    }

    private func startedGateway() throws -> Int {
        let port = try aFreePort()
        GatewayProcess.port = port
        XCTAssertEqual(GatewayProcess.start(settle: 0), .running)
        XCTAssertTrue(answers(on: port))
        return port
    }

    func testTheRecordedPortsAreEveryPortTheProcessWouldTakeDown() throws {
        let first = try startedGateway()
        XCTAssertEqual(GatewayHeldPorts.shared.current, [first],
                       "the answer to the build guard is read off this record from the event loop, "
                           + "so it is written wherever a listener changes")

        let second = try aFreePort()
        XCTAssertEqual(GatewayProcess.moveTo(port: second, settle: 0), .running)
        XCTAssertEqual(Set(GatewayHeldPorts.shared.current), Set([second, first]))

        GatewayProcess.closeTheRetiredListener()
        XCTAssertEqual(GatewayHeldPorts.shared.current, [second])

        GatewayProcess.stop()
        XCTAssertEqual(GatewayHeldPorts.shared.current, [],
                       "a stopped gateway takes nothing down, so the guard must not refuse for it")
    }

    func testTheNewPortIsBoundWhileTheOldListenerKeepsServing() throws {
        let first = try startedGateway()
        let second = try aFreePort()

        XCTAssertEqual(GatewayProcess.moveTo(port: second, settle: 0), .running)
        XCTAssertEqual(GatewayProcess.servingPort, second)
        XCTAssertEqual(GatewayProcess.retiredPort, first)
        XCTAssertTrue(answers(on: second))
        XCTAssertTrue(answers(on: first),
                      "every session that started before the change holds the old port in its own "
                          + "process environment and will never re-read anything")
    }

    func testABindThatFailsLeavesTheWorkingGatewayExactlyWhereItWas() throws {
        let working = try startedGateway()
        let stranger = NIOTestListener()
        stranger.onRequest = { _ in .fixed(status: 200, headers: [:], body: "mine") }
        try stranger.start()
        defer { stranger.stop() }

        let outcome = GatewayProcess.moveTo(port: stranger.port, settle: 0)
        XCTAssertFalse(outcome.isServing)
        XCTAssertEqual(GatewayProcess.port, working,
                       "stop-then-start moved the port before the start failed and left no gateway "
                           + "at all — the setup the user had a second ago")
        XCTAssertEqual(GatewayProcess.servingPort, working)
        XCTAssertNil(GatewayProcess.retiredPort, "a failed bind creates no listener to retire")
        XCTAssertTrue(answers(on: working))
        XCTAssertNotNil(GatewayProcess.lastPortRefusal,
                        "the panel has to say why, or the user sees a port that did not change and no reason")
    }

    func testASecondChangeClosesTheOneRetiredFirstSoAtMostTwoAreEverAlive() throws {
        let first = try startedGateway()
        let second = try aFreePort()
        XCTAssertEqual(GatewayProcess.moveTo(port: second, settle: 0), .running)
        let third = try aFreePort()
        XCTAssertEqual(GatewayProcess.moveTo(port: third, settle: 0), .running)

        XCTAssertEqual(GatewayProcess.servingPort, third)
        XCTAssertEqual(GatewayProcess.retiredPort, second)
        XCTAssertTrue(answers(on: third))
        XCTAssertTrue(answers(on: second))
        XCTAssertFalse(answers(on: first),
                       "without the cap this is an unbounded leak triggered from the UI")
    }

    func testChangingBackToTheRetiredPortReturnsToItWithoutABind() throws {
        let first = try startedGateway()
        let second = try aFreePort()
        XCTAssertEqual(GatewayProcess.moveTo(port: second, settle: 0), .running)

        XCTAssertEqual(GatewayProcess.moveTo(port: first, settle: 0), .running,
                       "a bind here would fail with EADDRINUSE against our own retired listener")
        XCTAssertEqual(GatewayProcess.servingPort, first)
        XCTAssertEqual(GatewayProcess.retiredPort, second)
        XCTAssertTrue(answers(on: first))
        XCTAssertTrue(answers(on: second), "the sessions on it never noticed anything")
    }

    func testApplyingThePortAlreadyServedChangesNothing() throws {
        let only = try startedGateway()
        XCTAssertEqual(GatewayProcess.moveTo(port: only, settle: 0), .running)
        XCTAssertEqual(GatewayProcess.servingPort, only)
        XCTAssertNil(GatewayProcess.retiredPort)
    }

    func testStoppingClosesTheRetiredListenerToo() throws {
        let first = try startedGateway()
        let second = try aFreePort()
        XCTAssertEqual(GatewayProcess.moveTo(port: second, settle: 0), .running)

        GatewayProcess.stop()
        XCTAssertNil(GatewayProcess.servingPort)
        XCTAssertNil(GatewayProcess.retiredPort)
        XCTAssertFalse(answers(on: first))
        XCTAssertFalse(answers(on: second))
    }

    func testARefusalDoesNotOutliveTheGatewayItDescribed() throws {
        let working = try startedGateway()
        let stranger = NIOTestListener()
        try stranger.start()
        XCTAssertFalse(GatewayProcess.moveTo(port: stranger.port, settle: 0).isServing)
        stranger.stop()
        XCTAssertNotNil(GatewayProcess.lastPortRefusal)

        GatewayProcess.stop()
        XCTAssertNil(GatewayProcess.lastPortRefusal,
                     "the orange line survived a Restart gateway and a disable/enable cycle, "
                         + "warning about a refusal that no longer described anything on screen")

        GatewayProcess.port = working
        XCTAssertEqual(GatewayProcess.start(settle: 0), .running)
        XCTAssertNil(GatewayProcess.lastPortRefusal)

        let again = NIOTestListener()
        try again.start()
        XCTAssertFalse(GatewayProcess.moveTo(port: again.port, settle: 0).isServing)
        again.stop()
        XCTAssertNotNil(GatewayProcess.lastPortRefusal)
        XCTAssertEqual(GatewayProcess.restart(on: working, settle: 0), .running)
        XCTAssertNil(GatewayProcess.lastPortRefusal,
                     "the Run the gateway toggle and the launch path both go through restart(on:), "
                         + "which is how the false line reached a user whose gateway was serving fine")
    }

    func testAFailedChangeWithNoListenerLeftIsReportedAsAFailureNotAsOff() throws {
        GatewayProcess.stop()
        XCTAssertNil(GatewayProcess.servingPort)
        let stranger = NIOTestListener()
        try stranger.start()
        defer { stranger.stop() }

        XCTAssertFalse(GatewayProcess.moveTo(port: stranger.port, settle: 0).isServing)
        XCTAssertEqual(GatewayProcess.status, .failed("the port could not be bound"),
                       "with nothing left serving, reported() falls through to notRunning unless the "
                           + "failure was recorded — and the menu renders notRunning as a gateway the "
                           + "user turned off, which is a normal state rather than a failure")
    }

    func testAFailedChangeWhileSomethingStillServesKeepsReportingRunning() throws {
        let working = try startedGateway()
        let stranger = NIOTestListener()
        try stranger.start()
        defer { stranger.stop() }

        XCTAssertFalse(GatewayProcess.moveTo(port: stranger.port, settle: 0).isServing)
        XCTAssertEqual(GatewayProcess.status, .running,
                       "the listener on \(working) never stopped, so the gateway is running; the "
                           + "refusal reaches the user through lastPortRefusal instead")
    }

    func testTheSettleHandedToStartIsTheOneTheRefusalActuallyUses() throws {
        let port = try aFreePort()
        GatewayProcess.port = port
        XCTAssertEqual(GatewayProcess.start(settle: 7), .running)
        XCTAssertEqual(GatewayProcess.settleInForce, 7,
                       "a settle the panel offers and the refusal ignores is a control that does "
                           + "nothing while the copy beside it claims otherwise")

        let second = try aFreePort()
        XCTAssertEqual(GatewayProcess.moveTo(port: second, settle: 3), .running)
        XCTAssertEqual(GatewayProcess.settleInForce, 3, "a port change carries it too")

        XCTAssertEqual(GatewayProcess.moveTo(port: port, settle: 11), .running)
        XCTAssertEqual(GatewayProcess.settleInForce, 11,
                       "a promotion returns to a listener built earlier, and it would otherwise keep "
                           + "the settle it was built with — two listeners disagreeing about a number "
                           + "the panel shows as one setting")
        XCTAssertEqual(GatewayProcess.retiredSettleInForce, 11,
                       "the retired listener serves sessions too, so the setting reaches it as well")
    }

    func testChangingTheSettleDisturbsNeitherListener() throws {
        let first = try startedGateway()
        let second = try aFreePort()
        XCTAssertEqual(GatewayProcess.moveTo(port: second, settle: 35), .running)
        XCTAssertEqual(GatewayProcess.retiredPort, first)

        GatewayProcess.applySettle(5)

        XCTAssertEqual(GatewayProcess.servingPort, second)
        XCTAssertEqual(GatewayProcess.retiredPort, first,
                       "the retired listener is serving sessions that started on it; changing an "
                           + "unrelated number is no reason to cut them off, and routing this through "
                           + "restart() would have done exactly that")
        XCTAssertTrue(answers(on: first))
        XCTAssertTrue(answers(on: second))
        XCTAssertEqual(GatewayProcess.settleInForce, 5)
        XCTAssertEqual(GatewayProcess.retiredSettleInForce, 5, "one setting, both listeners")
    }

    func testARunOfFailedAttemptsAccumulatesNothing() throws {
        let working = try startedGateway()
        for _ in 0..<3 {
            let stranger = NIOTestListener()
            try stranger.start()
            XCTAssertFalse(GatewayProcess.moveTo(port: stranger.port, settle: 0).isServing)
            stranger.stop()
        }
        XCTAssertEqual(GatewayProcess.servingPort, working)
        XCTAssertNil(GatewayProcess.retiredPort,
                     "the Try <port+1> button is clicked repeatedly by design, and a failed bind "
                         + "creates no listener, so only successful changes retire anything")
    }
}
