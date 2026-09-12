import XCTest
@testable import Hats

final class HatsCopyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let utc = TimeZone(identifier: "UTC")!

    private func hat(credentials: Bool = true, identity: Bool = true, refreshIn: TimeInterval? = 6 * 86400) -> Account {
        var hat = Account(id: "a", email: "filip@company.com", browser: nil)
        hat.hasStoredCredentials = credentials
        if identity { hat.identity = CLIIdentity(oauthAccount: [:], userID: nil) }
        hat.refreshExpiresAt = refreshIn.map { now.addingTimeInterval($0) }
        return hat
    }

    func testTheBlockerNamesTheOneThingThatFixesIt() {
        XCTAssertNil(HatsCopy.blocker(for: hat(), now: now))
        XCTAssertEqual(HatsCopy.blocker(for: hat(credentials: false), now: now), "needs login")
        XCTAssertEqual(HatsCopy.blocker(for: hat(identity: false), now: now), "needs one more login")
        XCTAssertEqual(HatsCopy.blocker(for: hat(refreshIn: -1), now: now), "login expired")
        XCTAssertEqual(HatsCopy.blocker(for: hat(credentials: false, refreshIn: -1), now: now), "needs login",
                       "the first thing missing is the one to name")
        XCTAssertEqual(HatsCopy.cannotWear("login expired"), "Cannot wear this hat — login expired")
    }

    func testExpiryIsShownOnlyInsideTheLastDay() {
        XCTAssertNil(HatsCopy.expiry(for: hat(refreshIn: 6 * 86400), now: now), "six days away is not news")
        XCTAssertEqual(HatsCopy.expiry(for: hat(refreshIn: 9 * 3600 + 40 * 60), now: now), "expires in 9h 40m")
        XCTAssertNil(HatsCopy.expiry(for: hat(refreshIn: -1), now: now), "expired is the blocker's job, not the expiry's")
        XCTAssertEqual(HatsCopy.loginValidity(for: hat(refreshIn: 6 * 86400 + 3 * 3600), now: now), "valid 6d 3h")
        XCTAssertEqual(HatsCopy.loginValidity(for: hat(refreshIn: -1), now: now), "expired")
    }

    func testTheParkedLineCarriesTheResetTimeAndAnObservedRise() throws {
        let now = try XCTUnwrap(UsageReading.date(from: "2026-08-31T20:00:00Z"))
        let ahead = try XCTUnwrap(UsageReading.date(from: "2026-08-31T23:20:00Z"))
        let behind = try XCTUnwrap(UsageReading.date(from: "2026-08-31T19:00:00Z"))
        let reading = UsageReading(session: UsageWindow(used: 5, limit: 100, resetsAt: ahead), weekly: nil)

        XCTAssertEqual(HatsCopy.parkedUsage(reading, timeZone: utc, now: now), "5% · resets 23:20",
                       "the one number a person needs in order to decide whether to switch is when the "
                           + "other hat is usable again")
        XCTAssertEqual(HatsCopy.parkedUsage(reading, rose: 4, timeZone: utc, now: now),
                       "5% · resets 23:20 · up 4 while not being worn",
                       "a rise while parked is the measurement, and it is what the operator read off the "
                           + "meter himself before the app would say it")
        XCTAssertEqual(HatsCopy.parkedUsage(reading, rose: 0, timeZone: utc, now: now), "5% · resets 23:20",
                       "zero is not a rise")
        let stale = UsageReading(session: UsageWindow(used: 5, limit: 100, resetsAt: behind), weekly: nil)
        XCTAssertEqual(HatsCopy.parkedUsage(stale, timeZone: utc, now: now), "5%",
                       "the poll is 300 s, so a parked reading outlives its own window; a reset time "
                           + "already past would be read as a future one")
    }

    func testTheUsageLineReadsPercentResetAndWeek() throws {
        let resets = try XCTUnwrap(UsageReading.date(from: "2026-08-30T18:52:00Z"))
        let reading = UsageReading(
            session: UsageWindow(used: 78, limit: 100, resetsAt: resets),
            weekly: UsageWindow(used: 41, limit: 100, resetsAt: nil)
        )
        let before = try XCTUnwrap(UsageReading.date(from: "2026-08-30T18:00:00Z"))
        XCTAssertEqual(HatsCopy.usageLine(reading, timeZone: utc, now: before),
                       "78% of 5h · resets 18:52 · week 41%")
        XCTAssertEqual(HatsCopy.usageLine(reading, timeZone: utc,
                                          now: try XCTUnwrap(UsageReading.date(from: "2026-08-30T19:00:00Z"))),
                       "78% of 5h · week 41%",
                       "the worn row shares the 300 s cadence, so a reset time already past is dropped "
                           + "there for the same reason as on a parked row")
        XCTAssertEqual(HatsCopy.usageLine(UsageReading(session: nil, weekly: reading.weekly),
                                          timeZone: utc, now: before), "week 41%")
        XCTAssertEqual(HatsCopy.parkedUsage(reading, timeZone: utc, now: before),
                       "78% · resets 18:52",
                       "without an explicit now this read the wall clock: it passed only because "
                           + "the fixture reset time is in the past, and would have included the "
                           + "clause on any machine running before it")
        XCTAssertNil(HatsCopy.parkedUsage(UsageReading(session: nil, weekly: reading.weekly)))
        XCTAssertEqual(HatsCopy.handover(to: "Personal"), "at the limit → Personal")
    }

    func testTheSessionsLineIsHonestAboutWhatItKnows() {
        XCTAssertEqual(HatsCopy.sessions(count: nil),
                       "Live sessions unknown — the process table could not be read")
        XCTAssertEqual(HatsCopy.sessions(count: 0), "No live sessions")
        XCTAssertEqual(HatsCopy.sessions(count: 1), "1 live session — which hat it keeps is not known")
        XCTAssertEqual(HatsCopy.sessions(count: 3),
                       "3 live sessions — which hats they keep is not known",
                       "a session that does not go through the gateway keeps whatever it started "
                           + "on, and the window says so in as many words: nobody here knows which "
                           + "hat that is. Naming the hat worn right now was the app contradicting "
                           + "itself, and it is what a tester compared against his profile")
    }

    func testTheSessionsLineCountsWhoGoesThroughTheGateway() {
        let url = "http://127.0.0.1:8787"
        let through = Session(pid: 1, elapsed: "1m", isInteractive: true, route: .pointedAt(url))
        let direct = Session(pid: 2, elapsed: "1m", isInteractive: true, route: .direct)
        let unknown = Session(pid: 3, elapsed: "1m", isInteractive: true)
        func line(_ live: [Session], serving: Bool = true) -> String {
            HatsCopy.sessions(.counted(live), gatewayBaseURLs: [url], serving: serving)
        }
        XCTAssertEqual(line([through], serving: false), "1 live session — pointed at the gateway, which is off",
                       "the header and the table row must agree that this session is stuck, not moved")
        XCTAssertEqual(line([through, direct], serving: false),
                       "2 live sessions — 1 pointed at the gateway, which is off, 1 not")
        XCTAssertEqual(line([through]), "1 live session — through the gateway")
        XCTAssertEqual(line([direct]),
                       "1 live session — not through the gateway, which hat it keeps is not known")
        XCTAssertEqual(line([through, through]), "2 live sessions — all through the gateway")
        XCTAssertEqual(line([direct, unknown]),
                       "2 live sessions — none through the gateway, which hats they keep is not known")
        XCTAssertEqual(line([through, direct, unknown]), "3 live sessions — 1 through the gateway, 2 not")
        XCTAssertEqual(line([]), "No live sessions")
        let onBoth = [
            Session(pid: 1, elapsed: "1m", isInteractive: true, route: .pointedAt("http://127.0.0.1:8788")),
            Session(pid: 2, elapsed: "1m", isInteractive: true, route: .pointedAt(url)),
        ]
        XCTAssertEqual(
            HatsCopy.sessions(.counted(onBoth),
                              gatewayBaseURLs: [url, "http://127.0.0.1:8788"], serving: true),
            "2 live sessions — all through the gateway",
            "while a listener is retiring both ports are ours, and counting one of them as somebody "
                + "else's understates who follows a switch"
        )
        XCTAssertEqual(
            HatsCopy.sessions(.counted(onBoth), gatewayBaseURLs: [url], serving: true),
            "2 live sessions — 1 through the gateway, 1 not"
        )

        XCTAssertEqual(HatsCopy.sessions(.unknown, gatewayBaseURLs: [url], serving: true),
                       "Live sessions unknown — the process table could not be read")
    }

    func testTheBannerNamesTimeLimitAndReturn() throws {
        let fired = try XCTUnwrap(UsageReading.date(from: "2026-08-30T13:52:00Z"))
        let resets = try XCTUnwrap(UsageReading.date(from: "2026-08-30T18:52:00Z"))
        let record = AutoSwitchRecord(firedAt: fired, from: "w", to: "p", limit: .session, resetsAt: resets)
        XCTAssertEqual(HatsCopy.banner(record, fromTitle: "Work", timeZone: utc),
                       "Switched automatically at 13:52 — Work reached its 5-hour limit · it comes back at 18:52")
        let unknown = AutoSwitchRecord(firedAt: fired, from: "w", to: "p", limit: .weekly, resetsAt: nil)
        XCTAssertEqual(HatsCopy.banner(unknown, fromTitle: "Work", timeZone: utc),
                       "Switched automatically at 13:52 — Work reached its weekly limit")
        let nextWeek = try XCTUnwrap(UsageReading.date(from: "2026-09-04T18:52:00Z"))
        let weekly = AutoSwitchRecord(firedAt: fired, from: "w", to: "p", limit: .weekly, resetsAt: nextWeek)
        XCTAssertEqual(HatsCopy.banner(weekly, fromTitle: "Work", timeZone: utc),
                       "Switched automatically at 13:52 — Work reached its weekly limit · it comes back on Fri 4 Sep at 18:52",
                       "a reset days away must carry its day, or 18:52 reads as tonight")
    }

    func testTheGatewayLineIsShortWhenServingAndPlainWhenNot() {
        XCTAssertEqual(HatsCopy.gateway(.running), "Gateway on \(GatewayProcess.port)")
        XCTAssertEqual(HatsCopy.gateway(.notRunning), "Gateway is off — hats change at the next renewal")
        XCTAssertEqual(HatsCopy.gateway(.failed("the port could not be bound")),
                       "Gateway could not start: the port could not be bound")
    }

    func testANumberWhoseLatestCheckFailedSaysSoAndOneWhoseCredentialFailedDoesNot() {
        XCTAssertEqual(HatsCopy.staleReading(.fetchFailed("unreachable")),
                       "latest check failed — unreachable",
                       "a request that did not reach the usage service keeps the previous number, "
                           + "so the row has to say the number may be stale or it reads as current")
        XCTAssertEqual(HatsCopy.staleReading(.renewalFailed("http 500")),
                       "latest check failed — renewal http 500",
                       "a renewal that failed on a blip keeps the previous number too, so the same "
                           + "warning has to stand over it")
        XCTAssertNil(HatsCopy.staleReading(nil))

        for invalidating: UsageTrouble in [.credentialUnreadable, .nothingStored, .noTokenStored,
                                           .tokenExpired, .parkedNeedsLogin, .liveSlotUnknown] {
            XCTAssertNil(HatsCopy.staleReading(invalidating),
                         "\(invalidating) clears the number, so there is no stale figure to warn "
                             + "about and the row shows its own sentence instead")
        }
    }

    func testBothRowBranchesThatShowANumberAlsoShowAFailedLatestCheck() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/HatRowView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        XCTAssertEqual(text.components(separatedBy: "HatsCopy.staleReading(row.usageTrouble)").count - 1, 2,
                       "the row is an else-if chain, so a hat that keeps a number after a failed "
                           + "poll showed the percentage and nothing else — the pair the data now "
                           + "produces was invisible. Both branches that render a number, worn and "
                           + "parked, have to render this line too, and a SwiftUI body cannot be "
                           + "driven from here, so the wiring is asserted by reading it")
    }
}
