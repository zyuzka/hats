import XCTest
@testable import Hats

final class GatewayStopDecisionTests: XCTestCase {
    private func session(_ pid: Int32, port: Int?) -> Session {
        Session(pid: pid,
                elapsed: "01:00",
                isInteractive: true,
                route: port.map { .pointedAt("http://127.0.0.1:\($0)") } ?? .direct)
    }

    func testTurningItOnAsksNobodyAndDoesNotEvenLookAtTheProcessTable() {
        var looked = false
        let decision = GatewayStopDecision.of(
            enabled: true,
            ports: [8787],
            sessions: { looked = true; return [self.session(1, port: 8787)] }()
        )
        XCTAssertEqual(decision, .proceed)
        XCTAssertFalse(looked,
                       "reading the process table costs two ps calls on the main thread, and the "
                           + "answer cannot change what turning the gateway on does")
    }

    func testStoppingItWithNobodyThroughItAsksNothing() {
        XCTAssertEqual(GatewayStopDecision.of(enabled: false, ports: [8787], sessions: []), .proceed)
        XCTAssertEqual(
            GatewayStopDecision.of(enabled: false, ports: [8787],
                                   sessions: [session(1, port: nil), session(2, port: 9999)]),
            .proceed,
            "a direct session and one pointed at somebody else's port lose nothing when this "
                + "listener closes"
        )
    }

    func testStoppingItUnderALiveSessionNamesTheCostAndThePids() throws {
        let decision = GatewayStopDecision.of(
            enabled: false,
            ports: [8787],
            sessions: [session(4242, port: 8787), session(11, port: nil)]
        )
        guard case .ask(let cost) = decision else { return XCTFail("this is the case that must ask") }
        XCTAssertTrue(cost.contains("1 live session running through the gateway (pid 4242)"), cost)
        XCTAssertTrue(cost.contains("unset the gateway variables"),
                      "the cure is outside this app: nothing can take the variable back out of a "
                          + "shell that already has it")
    }

    func testTheRetiredListenerCountsAsWell() throws {
        let decision = GatewayStopDecision.of(
            enabled: false,
            ports: [8787, 8788],
            sessions: [session(7, port: 8788)]
        )
        guard case .ask(let cost) = decision else { return XCTFail("the retired port dies with the rest") }
        XCTAssertTrue(cost.contains("pid 7"), cost)
    }

    func testPidsAreSortedSoTheSentenceIsStableAcrossPolls() throws {
        let decision = GatewayStopDecision.of(
            enabled: false,
            ports: [8787],
            sessions: [session(900, port: 8787), session(12, port: 8787)]
        )
        guard case .ask(let cost) = decision else { return XCTFail("two dependants must ask") }
        XCTAssertTrue(cost.contains("2 live sessions running through the gateway (pid 12, 900)"), cost)
    }

    func testAProcessTableThatCouldNotBeReadAsksRatherThanAssumingItIsEmpty() throws {
        let decision = GatewayStopDecision.of(enabled: false, ports: [8787], sessions: nil)
        guard case .ask(let cost) = decision else {
            return XCTFail("silence must not read as nobody being there")
        }
        XCTAssertTrue(cost.contains("could not be read"), cost)
        XCTAssertFalse(cost.contains("pid"),
                       "naming no pid is the honest form when the table is what failed")
    }

    func testRestartingIsTheFourthDoorOfTheSameActAndAsksToo() throws {
        let decision = GatewayStopDecision.forARestart(
            ports: [8787],
            sessions: [session(4242, port: 8787), session(11, port: nil)]
        )
        guard case .ask(let cost) = decision else {
            return XCTFail("restart is stop() then start(): GatewayProcess.restart closes both "
                               + "listeners, the retired one included, before it binds again")
        }
        XCTAssertTrue(cost.contains("1 live session running through the gateway (pid 4242)"), cost)
        XCTAssertTrue(cost.contains("opens it again on the same port"),
                      "the cost differs from turning it off and the sentence must not be copied: "
                          + "something does take the listener's place, moments later")
        XCTAssertTrue(cost.contains("stays down until it can"),
                      "and the honest half is that binding again can fail")
    }

    func testRestartingWithNobodyThroughItAsksNothing() {
        XCTAssertEqual(GatewayStopDecision.forARestart(ports: [8787], sessions: []), .proceed)
        XCTAssertEqual(GatewayStopDecision.forARestart(ports: [8787],
                                                       sessions: [session(1, port: 9999)]),
                       .proceed)
    }

    func testARestartUnderAnUnreadableProcessTableAsks() throws {
        guard case .ask(let cost) = GatewayStopDecision.forARestart(ports: [8787], sessions: nil) else {
            return XCTFail("silence is not evidence that nobody is there")
        }
        XCTAssertTrue(cost.contains("could not be read"), cost)
    }

    func testTheQuestionIsTheSameShapeTheOtherTwoDoorsAsk() {
        let sessions = [session(4242, port: 8787)]
        let stopping = GatewayStopDecision.of(enabled: false, ports: [8787], sessions: sessions)
        XCTAssertNotNil(HatsCopy.quitCost(.counted(sessions)),
                        "quit asks under a live session, and the toggle stops the same listener")
        XCTAssertNotEqual(stopping, .proceed,
                          "the third door of one act: quit asks, build refuses, and this used to "
                              + "close the listener in silence")
    }
}
