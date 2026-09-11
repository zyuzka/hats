import XCTest
@testable import Hats

final class GatewayControlAccessTests: XCTestCase {
    func testOnlyALoopbackHostCarryingTheBoundPortReachesAControlPath() {
        XCTAssertTrue(GatewayPaths.isFromLoopback(host: "127.0.0.1:8787", boundTo: 8787))
        XCTAssertTrue(GatewayPaths.isFromLoopback(host: "localhost:8787", boundTo: 8787))
        XCTAssertTrue(GatewayPaths.isFromLoopback(host: "[::1]:8787", boundTo: 8787))
        XCTAssertTrue(GatewayPaths.isFromLoopback(host: "LOCALHOST:8787", boundTo: 8787))
    }

    func testAnUnbracketedIPv6HostIsRefusedAndTheSetDoesNotPretendOtherwise() {
        XCTAssertFalse(GatewayPaths.isFromLoopback(host: "::1", boundTo: 8787),
                       "RFC 7230 requires brackets around an IPv6 host in Host, and everything here "
                           + "sends them; splitting on the last colon turns ::1 into host \":\" with "
                           + "port 1, so the entry that used to sit in loopbackHosts for this form "
                           + "could never match — a guard that cannot fire, which is the same shape "
                           + "the third review pass deleted elsewhere on this branch")
        XCTAssertFalse(GatewayPaths.loopbackHosts.contains("::1"))
        XCTAssertTrue(GatewayPaths.loopbackHosts.contains("[::1]"),
                      "and the bracketed form both parses and is accepted")
    }

    func testANameThatIsNotLoopbackIsRefusedEvenOnTheRightPort() {
        XCTAssertFalse(GatewayPaths.isFromLoopback(host: "hats.attacker.test:8787", boundTo: 8787),
                       "this is the rebinding case: the request arrives on the loopback socket, so "
                           + "only the Host header distinguishes a page that resolved a name to "
                           + "127.0.0.1 from a local client")
    }

    func testTheWrongPortAndAMissingHostAreRefused() {
        XCTAssertFalse(GatewayPaths.isFromLoopback(host: "127.0.0.1:9999", boundTo: 8787))
        XCTAssertFalse(GatewayPaths.isFromLoopback(host: nil, boundTo: 8787))
        XCTAssertFalse(GatewayPaths.isFromLoopback(host: "", boundTo: 8787))
    }

    func testABarePortlessLoopbackHostIsOnlyRightWhenTheGatewayIsOnPortEighty() {
        XCTAssertFalse(GatewayPaths.isFromLoopback(host: "127.0.0.1", boundTo: 8787))
        XCTAssertTrue(GatewayPaths.isFromLoopback(host: "127.0.0.1", boundTo: 80))
    }

    func testThePollBuildsItsWorldOffTheMainQueue() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/AutoSwitchWatch.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let inside = try NSRegularExpression(
            pattern: #"queue\.async[\s\S]{0,200}?UsageWorld\.real"#
        )
        XCTAssertEqual(inside.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)), 1,
                       "the timer fires on .main, so a world built before the hop is built on the "
                           + "main thread. The slot inside it is a closure now, which is what makes "
                           + "the build cheap, and this pins the other half — that the build itself "
                           + "happens after the hop. Fourth site of one concept: the guards, the "
                           + "login-script check and the remembered sweep were the first three")
        XCTAssertFalse(text.contains("let world = UsageWorld.real"),
                       "and no world is bound outside the closure any more")
    }

    func testAReaderThatMissesTheMemoryDoesNotWaitTheWritersBudget() throws {
        XCTAssertLessThan(SessionDiscovery.readerBudget, ProcessTable.budget,
                          "the guards were moved onto the one-second memory, and a miss there still "
                              + "sweeps: two ps reads at the writers' budget each, on the main "
                              + "thread, behind a UI action. A reader answers a person and can say "
                              + "cannot-tell; a writer resolves which slot to write and cannot")

        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/Sessions.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let wired = try NSRegularExpression(
            pattern: #"everySessionSeenRecently[\s\S]{0,400}?ProcessTable\.read\([\s\S]{0,80}?within: readerBudget"#
        )
        XCTAssertEqual(wired.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)), 1,
                       "and the remembered sweep has to pass it, which a closure default cannot show "
                           + "any other way. sweptNow keeps everySessionThatHoldsAPort at the full "
                           + "budget, and a separate check holds that half")
    }

    func testNoGuardSweepsTheProcessTableOnTheMainThread() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/AppDelegate+Gateway.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        XCTAssertFalse(text.contains("everySessionThatHoldsAPort"),
                       "setGateway, restartGateway and quit all run from a UI action and then put a "
                           + "question to the user, so a second of staleness cannot change the "
                           + "answer while a five-second ps budget on the main thread can freeze the "
                           + "menu bar. The fresh sweep belongs to the writers, which resolve which "
                           + "slot to write from it — CLIState.sweptNow keeps it, and a separate "
                           + "check holds that")
    }

    func testThePublishedSessionIdIsAPrefixRatherThanTheKeyThatConsumesARefusal() {
        let full = "0bb0a1f2-3c4d-5e6f-7a8b-9c0d1e2f3a4b"
        let rows = GatewaySessions.noting([:], session: full, credential: "cc464558",
                                          status: 200, at: .now)
        let published = GatewaySessions.reported(rows, now: .now).first?["session"] as? String

        XCTAssertEqual(published, String(full.prefix(8)),
                       "the full id is the capability that consumes a session's one-shot "
                           + "post-switch refusal, and this body is served to anything that can "
                           + "reach the port")
        XCTAssertNotEqual(published, GatewayRefusal.sessionKey(full))
    }

    func testASessionAlreadyToldStaysToldWhileOtherIdsFloodPastTheCap() {
        let refusal = GatewayRefusal(settle: 0, account: "a@x.co")
        XCTAssertTrue(refusal.hasSwitched(to: "b@x.co"))
        let victim = "0bb0a1f2-3c4d-5e6f-7a8b-9c0d1e2f3a4b"

        for index in 0..<(GatewayRefusal.sessionsRemembered - 1) {
            _ = refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                     session: "early-\(index)")
        }

        XCTAssertTrue(refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                           session: victim),
                      "the real session is told once, which is the whole mechanism. It is told "
                          + "AFTER the memory is nearly full on purpose: with the victim as the "
                          + "oldest entry, evicting the oldest and clearing everything lose it at "
                          + "the same moment, and a case that cannot tell the two apart proves "
                          + "nothing about either")

        _ = refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                 session: "one-more-past-the-cap")

        XCTAssertFalse(refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                            session: victim),
                       "and it is not told again just because the memory filled up. Clearing the "
                           + "whole set at the cap let any local client reset it at will, so one "
                           + "overflow cost every running session a fresh 401; evicting the oldest "
                           + "entry instead costs the attacker one request per entry it wants gone")
    }

    func testEvictingTheOldestOnlyRaisesThePriceAndDoesNotCloseTheDoor() {
        let refusal = GatewayRefusal(settle: 0, account: "a@x.co")
        XCTAssertTrue(refusal.hasSwitched(to: "b@x.co"))
        let victim = "0bb0a1f2-3c4d-5e6f-7a8b-9c0d1e2f3a4b"
        XCTAssertTrue(refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                           session: victim))

        for index in 0...GatewayRefusal.sessionsRemembered {
            _ = refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                     session: "flood-\(index)")
        }

        XCTAssertTrue(refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                           session: victim),
                      "measured, not assumed: a flood past the cap DOES evict an entry that was "
                          + "already told, so bounded eviction mitigates rather than fixes. The "
                          + "property only holds while the key is something the client names, and "
                          + "binding a session to the connection instead is the recorded follow-up. "
                          + "This case exists so the limit is visible rather than believed away")
    }

    func testTheSetOfSessionsAlreadyToldDoesNotGrowWithoutBound() {
        let refusal = GatewayRefusal(settle: 0, account: "a@x.co")
        XCTAssertTrue(refusal.hasSwitched(to: "b@x.co"))

        for index in 0...GatewayRefusal.sessionsRemembered {
            _ = refusal.shouldRefuse(path: "/v1/messages", credential: "aaaaaaaa",
                                     session: "session-\(index)")
        }

        XCTAssertLessThanOrEqual(refusal.snapshot().sessionsMoved,
                                 GatewayRefusal.sessionsRemembered,
                                 "a local client could insert one key per request into a set that "
                                     + "only the next switch cleared")
    }
}
