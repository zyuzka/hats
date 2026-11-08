import XCTest
@testable import Hats

final class UpdateInstallGateTests: XCTestCase {
    private var decision = GatewayStopDecision.proceed
    private var answers: [Bool] = []
    private var asked: [String] = []
    private var notices: [String] = []
    private var installs = 0

    private func createGate() -> UpdateInstallGate {
        UpdateInstallGate(
            decideTheRestart: { [unowned self] in decision },
            confirm: { [unowned self] cost in
                asked.append(cost)
                return answers.isEmpty ? false : answers.removeFirst()
            },
            notify: { [unowned self] title, _ in notices.append(title) },
            beforeAsking: { ask in ask() }
        )
    }

    private func install() {
        installs += 1
    }

    func testWithNobodyThroughTheGatewaySparkleRestartsWithoutAQuestion() {
        let gate = createGate()
        let postponed = gate.shouldPostponeTheRestart(version: "0.4.1", install: install)
        XCTAssertFalse(postponed, "not postponing is what lets Sparkle install and relaunch on its own")
        XCTAssertTrue(asked.isEmpty, "nothing is lost, so nobody is asked")
        XCTAssertEqual(
            installs,
            0,
            "Sparkle carries on by itself; the gate does not call the handler as well"
        )
        XCTAssertFalse(gate.hasAnInstallWaiting)
    }

    func testLaterKeepsTheInstallWithoutRunningIt() {
        decision = .ask("1 live session")
        answers = [
            false,
        ]
        let gate = createGate()
        let postponed = gate.shouldPostponeTheRestart(version: "0.4.1", install: install)
        XCTAssertTrue(postponed)
        XCTAssertEqual(
            asked,
            [
                "1 live session",
            ]
        )
        XCTAssertEqual(
            installs,
            0,
            "Later must not restart Hats"
        )
        XCTAssertTrue(gate.hasAnInstallWaiting, "Sparkle installs the waiting update when Hats quits")
    }

    func testTheNextCheckAsksAgainAndInstallRunsTheKeptInstall() {
        decision = .ask("1 live session")
        answers = [
            false,
            true,
        ]
        let gate = createGate()
        _ = gate.shouldPostponeTheRestart(version: "0.4.1", install: install)
        gate.askAboutTheWaitingInstall()
        XCTAssertEqual(
            asked.count,
            2,
            "Check for Updates while an update waits asks the same question again"
        )
        XCTAssertEqual(installs, 1)
        XCTAssertFalse(gate.hasAnInstallWaiting)
    }

    func testAskingAgainWithNobodyLeftNamesTheWaitingUpdate() {
        decision = .ask("1 live session")
        let gate = createGate()
        _ = gate.shouldPostponeTheRestart(version: "0.4.1", install: install)
        decision = .proceed
        gate.askAboutTheWaitingInstall()
        XCTAssertEqual(
            asked.last,
            HatsCopy.updateWaitsForQuit,
            "with no session at risk the question still asks before quitting Hats"
        )
        XCTAssertEqual(installs, 0)
    }

    func testAnAbortedSessionForgetsTheWaitingInstall() {
        decision = .ask("1 live session")
        let gate = createGate()
        _ = gate.shouldPostponeTheRestart(version: "0.4.1", install: install)
        gate.forgetTheWaitingInstall()
        gate.askAboutTheWaitingInstall()
        XCTAssertFalse(gate.hasAnInstallWaiting)
        XCTAssertEqual(
            asked.count,
            1,
            "a handler from an ended session installs nothing, so it is not offered"
        )
    }

    func testTheSameVersionIsAnnouncedOnce() {
        let gate = createGate()
        gate.announceOnce(version: "0.4.1")
        gate.announceOnce(version: "0.4.1")
        gate.announceOnce(version: "0.4.2")
        XCTAssertEqual(
            notices,
            [
                "Hats 0.4.1 is out",
                "Hats 0.4.2 is out",
            ],
            "Remind Me Later brings the same window back every six hours, the notification only once"
        )
    }
}
