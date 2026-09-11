import XCTest
@testable import Hats

final class GatewayPortChangeTests: XCTestCase {
    private func session(_ pid: Int32, at url: String?) -> Session {
        Session(pid: pid, elapsed: "01:00", isInteractive: true,
                route: url.map { SessionRoute.pointedAt($0) } ?? .unknown)
    }

    func testAPortWeAlreadyHoldIsPromotedRatherThanBound() {
        XCTAssertEqual(GatewayPortChange.plan(servingPort: 8787, retiredPort: nil, requested: 8787),
                       .unchanged)
        XCTAssertEqual(GatewayPortChange.plan(servingPort: 8788, retiredPort: 8787, requested: 8787),
                       .promoteRetired,
                       "binding here would fail with EADDRINUSE against our own retired listener, "
                           + "so the app would refuse to return to a port that works and is ours")
        XCTAssertEqual(GatewayPortChange.plan(servingPort: 8788, retiredPort: 8787, requested: 8789),
                       .bind)
        XCTAssertEqual(GatewayPortChange.plan(servingPort: nil, retiredPort: nil, requested: 8787),
                       .bind, "with nothing serving there is nothing to promote")
        XCTAssertEqual(GatewayPortChange.plan(servingPort: nil, retiredPort: 8787, requested: 8787),
                       .promoteRetired)
    }

    func testARetiredListenerIsHeldOpenByTheSessionsThatPointAtItAndByNothingElse() {
        let onIt = session(1, at: "http://127.0.0.1:8787")
        let elsewhere = session(2, at: "http://127.0.0.1:8788")
        let direct = Session(pid: 3, elapsed: "01:00", isInteractive: true, route: .direct)
        let unreadable = session(4, at: nil)

        XCTAssertTrue(GatewayRetirement.isStillDependedOn(port: 8787, by: [onIt, elsewhere]))
        XCTAssertFalse(GatewayRetirement.isStillDependedOn(port: 8787, by: [elsewhere, direct]))
        XCTAssertFalse(GatewayRetirement.isStillDependedOn(port: 8787, by: []),
                       "the last session on it exited, so the listener goes — no timer, nothing guessed")
        XCTAssertFalse(GatewayRetirement.isStillDependedOn(port: 8787, by: [unreadable]),
                       "a process whose environment cannot be read is another user's shell, which "
                           + "reads their own profile and cannot point at this gateway; treating it "
                           + "as ours would pin the listener open forever")
        XCTAssertTrue(GatewayRetirement.isStillDependedOn(port: 8787, by: nil),
                       "an unreadable process table is not evidence that nobody is there")
    }

    func testAnIdleSessionStillCountsBecauseIdleIsNotUnneeded() {
        let fridayEvening = Session(pid: 9, elapsed: "3-01:14:22", isInteractive: true,
                                    route: .pointedAt("http://127.0.0.1:8787"))
        XCTAssertTrue(GatewayRetirement.isStillDependedOn(port: 8787, by: [fridayEvening]),
                      "three days without a request is a pause, not an ending; no clock tells "
                          + "them apart, which is why the condition is dependency and not traffic")
    }

    func testADeadRetiredListenerIsReleasedRatherThanLeftHoldingItsThreads() {
        XCTAssertEqual(GatewayRetirement.verdict(hasRetired: false, retiredPort: nil, sessions: []),
                       .nothingRetired)
        XCTAssertEqual(GatewayRetirement.verdict(hasRetired: true, retiredPort: nil, sessions: []),
                       .releaseIt,
                       "a retired listener that stopped serving still owns an event-loop group, and "
                           + "guarding on the port alone made it invisible to the release check")
        XCTAssertEqual(GatewayRetirement.verdict(hasRetired: true, retiredPort: 8787, sessions: []),
                       .releaseIt)
        XCTAssertEqual(
            GatewayRetirement.verdict(hasRetired: true, retiredPort: 8787,
                                      sessions: [self.session(1, at: "http://127.0.0.1:8787")]),
            .keepIt
        )
        XCTAssertEqual(GatewayRetirement.verdict(hasRetired: true, retiredPort: 8787, sessions: nil),
                       .keepIt, "an unreadable process table is not evidence that nobody is there")
    }

    func testAPortIsDependedOnWhateverSpellingTheSessionUsedForTheHost() {
        for spelling in ["http://127.0.0.1:8787", "http://localhost:8787", "http://[::1]:8787"] {
            XCTAssertTrue(GatewayRetirement.isStillDependedOn(port: 8787, by: [session(1, at: spelling)]),
                          "closing a listener is destructive, so it errs towards keeping it: \(spelling)")
        }
        XCTAssertFalse(GatewayRetirement.isStillDependedOn(port: 8787,
                                                           by: [session(1, at: "http://localhost:8788")]),
                       "a different port is a different listener whatever the host is called")
    }

    func testEverySpellingThatReachesOurBindHoldsTheListenerOpen() {
        let reach = ["http://127.0.0.1:8787", "http://127.1:8787", "http://127.0.1:8787",
                     "http://2130706433:8787", "http://0177.0.0.1:8787",
                     "http://localhost:8787", "http://localhost.:8787",
                     "http://[::1]:8787", "http://127.0.0.1:8787/v1"]
        for spelling in reach {
            XCTAssertTrue(GatewayRetirement.isStillDependedOn(port: 8787, by: [session(1, at: spelling)]),
                          "an allow-list of spellings is a list of the ones I thought of; 127.1, "
                              + "127.0.1 and 2130706433 are all 127.0.0.1 and all reach the bind: "
                              + spelling)
        }
        let doNotReach = ["http://127.0.0.2:8787", "http://192.168.1.10:8787",
                          "http://example.com:8787", "http://localhost:8788"]
        for spelling in doNotReach {
            XCTAssertFalse(GatewayRetirement.isStillDependedOn(port: 8787, by: [session(1, at: spelling)]),
                           "a socket bound to 127.0.0.1 does not answer these, so a session on one "
                               + "is not depending on it: " + spelling)
        }
    }

    func testAStrangerOnOurPortNumberSomewhereElseIsNotADependant() {
        for elsewhere in ["https://my-company-proxy.internal:8787/v1",
                          "http://example.com:8787",
                          "http://192.168.1.10:8787"] {
            XCTAssertFalse(GatewayRetirement.isStillDependedOn(port: 8787,
                                                               by: [session(1, at: elsewhere)]),
                           "a port number is not an address: our listener is on loopback, and counting "
                               + "\(elsewhere) as a dependant would pin it open for a session that "
                               + "never reached us")
        }
        XCTAssertTrue(GatewayRetirement.isStillDependedOn(port: 8787,
                                                          by: [session(1, at: "http://127.0.0.1:8787")]),
                      "and the loopback spellings still hold it open")
    }

    func testTheDisplayLabelKeepsItsNarrowerMeaning() {
        XCTAssertFalse(SessionRoute.pointedAt("http://localhost:8787")
            .isThrough(gatewayAt: "http://127.0.0.1:8787"),
                       "isThrough answers a question about what the table shows and stays exact; "
                           + "only the destructive decision widens")
    }

    func testABatchSessionHoldsThePortJustAsAnInteractiveOneDoes() {
        let oneShot = Session(pid: 7, elapsed: "00:20", isInteractive: false,
                              route: .pointedAt("http://127.0.0.1:8787"))
        XCTAssertTrue(GatewayRetirement.isStillDependedOn(port: 8787, by: [oneShot]),
                      "the interactive filter is a display filter, not a dependency one — a claude -p "
                          + "run through the gateway loses its port just the same")
    }

    func testDependantsOfSeveralPortsIsTheUnionAndNotTheFirstMatch() {
        let sessions = [session(1, at: "http://127.0.0.1:8787"),
                        session(2, at: "http://localhost:8788"),
                        session(3, at: "http://127.0.0.1:9999")]
        XCTAssertEqual(GatewayRetirement.dependants(onAnyOf: [8787, 8788], among: sessions).map(\.pid),
                       [1, 2],
                       "both listeners live in one process, so both ports are one blast radius")
        XCTAssertEqual(GatewayRetirement.dependants(onAnyOf: [], among: sessions), [],
                       "no ports held means nothing depends on this app")
    }

    func testTheRetiredListenerLineSaysWhoIsOnItAndWhatApplyingWillDo() {
        XCTAssertEqual(HatsCopy.retiredListener(port: 8787, dependants: 3, keptByTheTypedPort: false),
                       "port 8787 is still listening for 3 live sessions — applying a different port closes it")
        XCTAssertEqual(HatsCopy.retiredListener(port: 8787, dependants: 1, keptByTheTypedPort: false),
                       "port 8787 is still listening for 1 live session — applying a different port closes it")
        XCTAssertEqual(HatsCopy.retiredListener(port: 8787, dependants: 0, keptByTheTypedPort: false),
                       "port 8787 is still listening for no live session — applying a different port closes it")
        XCTAssertEqual(HatsCopy.retiredListener(port: 8787, dependants: nil, keptByTheTypedPort: false),
                       "port 8787 is still listening for sessions that could not be counted — "
                           + "applying a different port closes it")
        XCTAssertEqual(HatsCopy.retiredListener(port: 8787, dependants: 2, keptByTheTypedPort: true),
                       "port 8787 is still listening for 2 live sessions — applying it moves back to that listener")
    }

    func testTheSnapshotCountsOnlyTheSessionsPointedAtTheRetiredPort() {
        var snapshot = HatsSnapshot()
        snapshot.everySession = [session(1, at: "http://127.0.0.1:8787"),
                                 session(2, at: "http://127.0.0.1:8787/"),
                                 session(3, at: "http://127.0.0.1:8788")]
        XCTAssertEqual(snapshot.sessionsThrough(port: 8787), 2)
        XCTAssertEqual(snapshot.sessionsThrough(port: 8788), 1)
        snapshot.everySession = nil
        XCTAssertNil(snapshot.sessionsThrough(port: 8787),
                     "an unreadable process table has no count, and zero would be a lie")
    }

    func testThePanelCountsTheSameSessionsTheReleaseDecisionCounts() {
        let oneShot = Session(pid: 9, elapsed: "00:30", isInteractive: false,
                              route: .pointedAt("http://127.0.0.1:8787"))
        var snapshot = HatsSnapshot()
        snapshot.sessions = .counted([])
        snapshot.everySession = [oneShot]

        XCTAssertEqual(snapshot.sessionsThrough(port: 8787), 1,
                       "the panel used to count from the interactive-only list while the release "
                           + "decision counted one-shots, so it printed 'no live session' beside a "
                           + "listener that would never be released")
        XCTAssertEqual(GatewayRetirement.verdict(hasRetired: true, retiredPort: 8787,
                                                 sessions: snapshot.everySession),
                       .keepIt,
                       "and the sentence the user reads must agree with the verdict the app acts on")
    }
}
