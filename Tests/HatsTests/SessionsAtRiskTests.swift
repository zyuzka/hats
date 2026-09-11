import XCTest
@testable import Hats

final class SessionsAtRiskTests: XCTestCase {
    private func session(_ pid: Int32, _ route: SessionRoute) -> Session {
        Session(pid: pid, elapsed: "01:00", isInteractive: true, route: route)
    }

    func testTheAnswerNamesEverySessionOnTheGatewaysPort() {
        let text = SessionsAtRisk.text(ports: [8787], sessions: [
            session(80442, .pointedAt("http://127.0.0.1:8787")),
            session(47193, .pointedAt("http://localhost:8787")),
            session(999, .direct),
        ])
        XCTAssertEqual(text, "readable 1\npid 47193\npid 80442\n",
                       "pids are sorted so the refusal reads the same way twice, and a direct session is not at risk")
    }

    func testTheSpellingsTheAppAcceptsAreTheOnesTheGuardGets() {
        for host in ["127.0.0.1", "localhost", "localhost.", "127.0.0.01", "0177.0.0.1", "127.1"] {
            let text = SessionsAtRisk.text(ports: [8787], sessions: [
                session(1, .pointedAt("http://\(host):8787")),
            ])
            XCTAssertEqual(text, "readable 1\npid 1\n",
                           "\(host) is loopback to inet_aton, so the app counts it and the guard must hear about it")
        }
        for host in ["127.0.0.2", "api.anthropic.com", "128.0.0.1"] {
            let text = SessionsAtRisk.text(ports: [8787], sessions: [
                session(1, .pointedAt("http://\(host):8787")),
            ])
            XCTAssertEqual(text, "readable 1\n",
                           "\(host) is not the gateway, and the gateway binds 127.0.0.1 alone")
        }
    }

    func testAnotherPortIsAnotherGateway() {
        let sessions = [session(1, .pointedAt("http://127.0.0.1:9999"))]
        XCTAssertEqual(SessionsAtRisk.text(ports: [8787], sessions: sessions), "readable 1\n")
        XCTAssertEqual(SessionsAtRisk.text(ports: [9999], sessions: sessions), "readable 1\npid 1\n")
    }

    func testAnUnreadableProcessTableIsSaidRatherThanReportedAsNothing() {
        XCTAssertEqual(SessionsAtRisk.text(ports: [8787], sessions: nil), "readable 0\n",
                       "nil is ps having failed; the guard reads readable 0 as unknown and refuses")
        XCTAssertEqual(SessionsAtRisk.text(ports: [8787], sessions: []), "readable 1\n",
                       "an empty list is a measurement, and it means nothing is at risk")
    }

    func testARetiredListenerPortIsAskedAboutTogetherWithTheServingOne() {
        let sessions = [
            session(1, .pointedAt("http://127.0.0.1:8787")),
            session(2, .pointedAt("http://127.0.0.1:8788")),
            session(3, .pointedAt("http://127.0.0.1:9999")),
        ]
        XCTAssertEqual(SessionsAtRisk.text(ports: [8788, 8787], sessions: sessions),
                       "readable 1\npid 1\npid 2\n",
                       "one process holds both listeners, so killing it takes down the sessions on "
                           + "the retired port as well and the guard has to hear about both")
    }

    func testAPortNamedTwiceNamesItsSessionOnce() {
        let sessions = [session(1, .pointedAt("http://127.0.0.1:8787"))]
        XCTAssertEqual(SessionsAtRisk.text(ports: [8787, 8787], sessions: sessions),
                       "readable 1\npid 1\n",
                       "the serving port arrives twice whenever nothing is retired")
    }

    func testAOneShotSessionIsNamedBecauseItLosesThePortJustTheSame() {
        let oneShot = Session(pid: 5, elapsed: "00:20", isInteractive: false,
                              route: .pointedAt("http://127.0.0.1:8787"))
        XCTAssertEqual(SessionsAtRisk.text(ports: [8787], sessions: [oneShot]),
                       "readable 1\npid 5\n",
                       "the interactive filter is a display filter, not a dependency one")
    }

    func testTheBodyIsTheTextAsBytes() {
        let sessions = [session(7, .pointedAt("http://127.0.0.1:8787"))]
        XCTAssertEqual(SessionsAtRisk.body(ports: [8787], sessions: sessions),
                       Data(SessionsAtRisk.text(ports: [8787], sessions: sessions).utf8))
    }
}
