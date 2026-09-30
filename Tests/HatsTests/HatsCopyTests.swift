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

    func testTheBannerOfABlindSwitchPromisesNoReturn() throws {
        let fired = try XCTUnwrap(UsageReading.date(from: "2026-08-30T13:52:00Z"))
        let blind = AutoSwitchRecord(firedAt: fired, from: "w", to: "p", limit: .session,
                                     resetsAt: nil, cause: .usageCouldNotBeRead)
        XCTAssertEqual(HatsCopy.banner(blind, fromTitle: "Work", timeZone: utc),
                       "Switched automatically at 13:52 — Work's usage could not be read",
                       "the record carries a limit so an older build can still read the file, and "
                           + "the banner must not read it as a limit that was crossed - the cause "
                           + "is what decides the sentence. No window was crossed, so there is no "
                           + "window to come back and no hour to name one at")
        let older = AutoSwitchRecord(firedAt: fired, from: "w", to: "p", limit: .session,
                                     resetsAt: nil, cause: nil)
        XCTAssertEqual(HatsCopy.banner(older, fromTitle: "Work", timeZone: utc),
                       "Switched automatically at 13:52 — Work reached its 5-hour limit",
                       "a record written before this change carries no cause at all, and an absent "
                           + "cause is indistinguishable from a default, so the limit it does carry "
                           + "is what decides — the banner is built from the file after a restart")
    }

    private func shutOut(_ id: String, _ title: String, _ blocker: String = "needs login") -> ShutOutHat {
        ShutOutHat(id: id, title: title, blocker: blocker, loginAction: "Log in again…")
    }

    private func strandedBody(
        _ by: AutoSwitchDeadEnd.StrandedBy,
        limit: UsageLimit = .session,
        at when: Date
    ) -> String {
        HatsCopy.nowhereToGo(of: "Work", limit: limit, strandedBy: by,
                             now: when, timeZone: utc).1
    }

    func testTheDeadEndNamesTheOneThingThePersonCanDoAboutIt() throws {
        let when = try XCTUnwrap(UsageReading.date(from: "2026-09-25T10:45:00Z"))
        let thisAfternoon = try XCTUnwrap(UsageReading.date(from: "2026-09-25T13:00:00Z"))
        let nextThursday = try XCTUnwrap(UsageReading.date(from: "2026-10-01T13:00:00Z"))

        XCTAssertEqual(strandedBody(.noOtherHat, at: when),
                       "Work reached its 5-hour limit. There is no other hat to switch to.",
                       "one hat and no hour: there is nothing to wait for, so naming a time would "
                           + "answer a question nobody is in a position to ask")
        XCTAssertEqual(strandedBody(.othersNeedSigningIn(shutOut("personal", "Personal"), alsoShutOut: []), at: when),
                       "Work reached its 5-hour limit, and Personal has room but needs login.",
                       "the hat is named because the person is being asked to do something to it, "
                           + "and no hour because the answer is an action, not a wait")
        XCTAssertEqual(strandedBody(.othersNeedSigningIn(shutOut("personal", "Personal"),
                                                         alsoShutOut: [shutOut("team", "Team", "login expired")]),
                                    at: when),
                       "Work reached its 5-hour limit, and the other hats have room but none "
                           + "of them can be worn.",
                       "with more than one there is neither a single name to give nor a single "
                           + "reason: one needs a first login and the other one expired, and "
                           + "\"need signing in again\" would be wrong about the first")
        XCTAssertEqual(strandedBody(.othersAreSpent(freesUpAt: thisAfternoon), at: when),
                       "Work reached its 5-hour limit, and no other hat has room. Something frees "
                           + "up at 13:00, or sooner if you reset a limit.",
                       "here waiting IS the answer, so the hour is named - and the reset is named "
                           + "with it, because a full reset on the web turns any hour into a "
                           + "prediction the person can cancel with a button")
        XCTAssertEqual(strandedBody(.othersAreSpent(freesUpAt: nextThursday), limit: .weekly, at: when),
                       "Work reached its weekly limit, and no other hat has room. Something frees "
                           + "up on Thu 1 Oct at 13:00, or sooner if you reset a limit.",
                       "a week away carries its day, or 13:00 reads as this afternoon")
        XCTAssertEqual(strandedBody(.othersAreSpent(freesUpAt: nil), at: when),
                       "Work reached its 5-hour limit, and no other hat has room.",
                       "no known reset anywhere, so the sentence says less rather than guessing - "
                           + "and the reset hint goes with it, since it hangs off the hour")
        XCTAssertEqual(strandedBody(.othersAreSpent(freesUpAt: when.addingTimeInterval(-3600)), at: when),
                       strandedBody(.othersAreSpent(freesUpAt: nil), at: when),
                       "the reading reaching this sentence need not be fresh - crossedLimit asks "
                           + "nothing about its age - so a window that has already run out names "
                           + "an hour in the past, which is the app lying about the one thing this "
                           + "branch exists to tell the truth about")
    }

    func testTheSpokenLabelIsShortBecauseItIsReadOnEveryGlance() {
        XCTAssertEqual(HatsCopy.nowhereToGoAloud(limit: .session), "5-hour limit reached, nowhere to go")
        XCTAssertEqual(HatsCopy.nowhereToGoAloud(limit: .weekly), "weekly limit reached, nowhere to go")
        XCTAssertEqual(AutoSwitchWarning.nowhereToGoAtALimit(.session, .noOtherHat).menuBarLabel,
                       AutoSwitchWarning.nowhereToGoAtALimit(
                           .session, .othersAreSpent(freesUpAt: now)
                       ).menuBarLabel,
                       "the label names the limit and says there is nowhere to go, and stops - the "
                           + "argument that a reset hint repeated on every focus stops being advice "
                           + "applies to fifteen words of narration as much as to five of advice. "
                           + "Which dead end it is, and the hour, live in the banner, which is read "
                           + "on purpose rather than on every glance")
    }

    func testTheWarningsAboutAUsageThatCannotBeReadAreWrittenForTheHuman() {
        let willSwitch = HatsCopy.cannotReadTheUsage(of: "Work")
        XCTAssertEqual(willSwitch.0, "Can't read usage")
        XCTAssertEqual(willSwitch.1,
                       "Hats can't read Work's usage. It will switch to a hat with room as soon as it can.",
                       "no count of failures in the line: the warning is raised once an episode, "
                           + "so a number would go stale the moment it was shown")
        let stuck = HatsCopy.cannotReadTheUsageAndHasNowhereToGo(of: "Work")
        XCTAssertEqual(stuck.0, "Can't read usage")
        XCTAssertEqual(stuck.1,
                       "Hats can't read Work's usage, and no other hat has a fresh reading to switch to.")
        let spent = HatsCopy.cannotReadTheUsageAndTheOthersAreSpent(of: "Work")
        XCTAssertEqual(spent.0, "Can't read usage")
        XCTAssertEqual(spent.1, "Hats can't read Work's usage, and the other hats are spent.")

        let everyWarning: [AutoSwitchWarning] = [
            .willSwitchWhenItCan,
            .nowhereFreshToGo,
            .everyOtherHatIsSpent,
            .nowhereToGoAtALimit(.session, .othersAreSpent(freesUpAt: nil)),
        ]
        let written = everyWarning.map { $0.text(hat: "Work", now: now, timeZone: utc) }
        XCTAssertEqual(Set(written.map(\.1)).count, everyWarning.count,
                       "one sentence per dead end: the hats being spent is not the hats being "
                           + "unread, telling a person the others have no fresh reading when they "
                           + "do is the kind of small lie this whole branch exists to stop, and "
                           + "reaching a limit that was measured is not failing to measure one. "
                           + "This list is the check - a fifth warning added beside it rather "
                           + "than into it would be covered by nothing")
        XCTAssertEqual(Set(written.dropLast().map(\.0)).count, 1,
                       "the three that cannot read the usage share a title on purpose; it names "
                           + "the one thing all three have in common")
        XCTAssertEqual(written.last?.0, "Nowhere to switch",
                       "and the fourth does not share it, because the usage was read perfectly "
                           + "and \"Can't read usage\" over it would be false")
        XCTAssertEqual(Set(everyWarning.map(\.menuBarLabel)).count, 2,
                       "read aloud there are two facts, not four: the usage cannot be read, or "
                           + "the limit was reached and nothing has room")
        XCTAssertEqual(HatsCopy.switched(to: "Personal"), "Switched to Personal")
        XCTAssertEqual(
            HatsCopy.switchedBecauseTheUsageWasUnreadable(
                from: "Work", lastSeen: LastLiveWindow(limit: .weekly, percent: 88), age: 7380
            ),
            "Hats couldn't read Work's usage. Its weekly limit was at 88% when last seen 2h 3m ago."
        )
        XCTAssertEqual(
            HatsCopy.switchedBecauseTheUsageWasUnreadable(
                from: "Work", lastSeen: LastLiveWindow(limit: .weekly, percent: 88)
            ),
            "Hats couldn't read Work's usage. Its weekly limit was at 88% when last seen.",
            "an age nobody could measure is left out rather than guessed at"
        )
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
