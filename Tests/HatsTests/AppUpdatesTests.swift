import XCTest
@testable import Hats

final class AppUpdatesTests: XCTestCase {
    private let feed = "https://github.com/zyuzka/hats/releases/latest/download/appcast.xml"
    private let gatewayPorts = [
        8787,
    ]

    private func session(_ pid: Int32, port: Int?) -> Session {
        Session(
            pid: pid,
            elapsed: "01:00",
            isInteractive: true,
            route: port.map { .pointedAt("http://127.0.0.1:\($0)") } ?? .direct
        )
    }

    private func unreadSession(_ pid: Int32) -> Session {
        Session(pid: pid, elapsed: "01:00", isInteractive: true)
    }

    func testASessionWhoseSettingsCouldNotBeReadMakesTheUpdateAsk() throws {
        let decision = GatewayStopDecision.getForAnUpdate(
            ports: gatewayPorts,
            sessions: [
                unreadSession(31),
                session(2, port: nil),
            ]
        )
        guard case .ask(let cost) = decision else {
            return XCTFail("a session whose environment could not be read may be pointed at the gateway")
        }
        XCTAssertTrue(cost.contains("The settings of 1 session (pid 31) could not be read"), cost)
        XCTAssertTrue(cost.contains("A request going through the gateway at that moment is cut off"), cost)
    }

    func testAnUnreadSessionBesideALiveOneIsNamedToo() throws {
        let decision = GatewayStopDecision.getForAnUpdate(
            ports: gatewayPorts,
            sessions: [
                session(4242, port: 8787),
                unreadSession(31),
            ]
        )
        guard case .ask(let cost) = decision else { return XCTFail("a live session through the gateway asks") }
        XCTAssertTrue(cost.contains("1 live session running through the gateway (pid 4242)"), cost)
        XCTAssertTrue(cost.contains("(pid 31) could not be read"), cost)
    }

    func testAnUnreadSessionCostsNothingWhileTheGatewayHoldsNoPort() {
        let decision = GatewayStopDecision.getForAnUpdate(
            ports: [],
            sessions: [
                unreadSession(31),
            ]
        )
        XCTAssertEqual(
            decision,
            .proceed,
            "with nothing listening, a restart cannot cut a session off"
        )
    }

    func testTheGatewayStopQuestionStillIgnoresUnreadSessions() {
        let stopping = GatewayStopDecision.of(
            enabled: false,
            ports: gatewayPorts,
            sessions: [
                unreadSession(31),
            ]
        )
        XCTAssertEqual(
            stopping,
            .proceed,
            "only the update decision counts an unread session; the gateway's own prompts do not"
        )
    }

    func testInstallingWithNobodyThroughTheGatewayRestartsWithoutASecondQuestion() {
        let nobody = GatewayStopDecision.getForAnUpdate(ports: gatewayPorts, sessions: [])
        let elsewhere = GatewayStopDecision.getForAnUpdate(
            ports: gatewayPorts,
            sessions: [
                session(1, port: nil),
                session(2, port: 9999),
            ]
        )
        XCTAssertEqual(nobody, .proceed)
        XCTAssertEqual(
            elsewhere,
            .proceed,
            "a direct session and one pointed at somebody else's port lose nothing when Hats restarts"
        )
    }

    func testInstallingUnderALiveSessionAsksAndNamesWhatIsCutOff() throws {
        let decision = GatewayStopDecision.getForAnUpdate(
            ports: gatewayPorts,
            sessions: [
                session(4242, port: 8787),
                session(11, port: nil),
            ]
        )
        guard case .ask(let cost) = decision else {
            return XCTFail("the restart closes the listener a live session is pointed at")
        }
        XCTAssertTrue(cost.contains("1 live session running through the gateway (pid 4242)"), cost)
        XCTAssertTrue(
            cost.contains("A request going through the gateway at that moment is cut off"),
            "the question has to say plainly that a request in flight is lost: closing the channel cancels the relay"
        )
        XCTAssertTrue(
            cost.contains("cannot take the port back"),
            "the new process binds again and may fail to, which is the other half of the cost"
        )
        XCTAssertTrue(
            cost.contains("Later installs the update the next time Hats quits"),
            "Later is not a refusal: Sparkle installs the waiting update on the next quit"
        )
    }

    func testTheRetiredListenerCountsForAnUpdateToo() throws {
        let decision = GatewayStopDecision.getForAnUpdate(
            ports: [
                8787,
                8788,
            ],
            sessions: [
                session(7, port: 8788),
            ]
        )
        guard case .ask(let cost) = decision else { return XCTFail("the retired port dies with the process") }
        XCTAssertTrue(cost.contains("pid 7"), cost)
    }

    func testAnUnreadableProcessTableAsksRatherThanAssumingNobodyIsThere() throws {
        guard case .ask(let cost) = GatewayStopDecision.getForAnUpdate(ports: gatewayPorts, sessions: nil) else {
            return XCTFail("silence is not evidence that nobody is there")
        }
        XCTAssertTrue(cost.contains("could not be read"), cost)
        XCTAssertTrue(cost.contains("Installing the update quits Hats"), cost)
    }

    func testWithTheGatewayHoldingNoPortAnUnreadableProcessTableDoesNotAsk() {
        XCTAssertEqual(
            GatewayStopDecision.getForAnUpdate(ports: [], sessions: nil),
            .proceed,
            "with no listener there is no request to cut off, whatever the process table says"
        )
    }

    func testTheUpdateCostIsNotTheGatewayRestartSentence() throws {
        let sessions = [
            session(4242, port: 8787),
        ]
        let update = try XCTUnwrap(HatsCopy.getUpdateInstallCost(ports: gatewayPorts, sessions: sessions))
        let restart = try XCTUnwrap(HatsCopy.gatewayRestartCost(ports: gatewayPorts, sessions: sessions))
        XCTAssertNotEqual(
            update,
            restart,
            "a restart of the gateway keeps Hats running; an update quits it and opens another version"
        )
    }

    func testOnlyABundleCarryingTheFeedAndTheKeyGetsAnUpdater() {
        let complete: [String: Any] = [
            "SUFeedURL": feed,
            "SUPublicEDKey": "a2V5",
        ]
        let blankKey: [String: Any] = [
            "SUFeedURL": feed,
            "SUPublicEDKey": "  ",
        ]
        let feedOnly: [String: Any] = [
            "SUFeedURL": feed,
        ]
        let keyOnly: [String: Any] = [
            "SUPublicEDKey": "a2V5",
        ]
        XCTAssertTrue(AppUpdates.isTheBundleConfigured(complete))
        XCTAssertFalse(
            AppUpdates.isTheBundleConfigured(nil),
            "a bare swift run binary has no Info.plist, and Sparkle would greet it with an alert"
        )
        XCTAssertFalse(AppUpdates.isTheBundleConfigured(feedOnly))
        XCTAssertFalse(AppUpdates.isTheBundleConfigured(blankKey))
        XCTAssertFalse(AppUpdates.isTheBundleConfigured(keyOnly))
    }
}
