import XCTest
@testable import Hats

final class VacationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let resetsAt = Date(timeIntervalSince1970: 1_800_003_600)
    private let sooner = Date(timeIntervalSince1970: 1_800_001_800)
    private let utc = TimeZone(identifier: "UTC")!
    private let awayB = HatOnVacation(id: "b", title: "B")
    private let awayC = HatOnVacation(id: "c", title: "C")
    private let awayD = HatOnVacation(id: "d", title: "D")

    private struct Seen {
        let outcome: AutoSwitchOutcome
        let holding: AutoSwitchHold?
        let warning: AutoSwitchWarning?
        let snapshot: HatsSnapshot
    }

    private func createHat(_ id: String, away: Bool = false) -> Account {
        var hat = createNeverSignedIn(id)
        hat.hasStoredCredentials = true
        hat.identity = CLIIdentity(oauthAccount: [:], userID: nil)
        if away { hat.vacationSince = now }

        return hat
    }

    private func createNeverSignedIn(_ id: String) -> Account {
        var hat = Account(
            id: id,
            email: "\(id)@x.co",
            browser: nil
        )
        hat.name = id.uppercased()

        return hat
    }

    private func createWindow(_ percent: Int, resets: Date?) -> UsageWindow {
        UsageWindow(
            used: percent,
            limit: 100,
            resetsAt: resets
        )
    }

    private func createReading(_ percent: Int, resets: Date? = nil) -> UsageReading {
        UsageReading(session: createWindow(percent, resets: resets ?? resetsAt), weekly: nil)
    }

    private func createReadingWithoutAReset(_ percent: Int) -> UsageReading {
        UsageReading(session: createWindow(percent, resets: nil), weekly: nil)
    }

    private func createReadingOfBothWindows(_ percent: Int) -> UsageReading {
        UsageReading(
            session: createWindow(percent, resets: resetsAt),
            weekly: createWindow(percent, resets: resetsAt)
        )
    }

    private func createArmed(_ order: [String]) -> AutoSwitchPolicy {
        var policy = AutoSwitchPolicy()
        policy.isOn = true
        policy.order = order

        return policy
    }

    private func createSnapshot(
        _ hats: [Account],
        wearing: String = "a",
        readings: [String: UsageReading],
        order: [String] = [
            "b",
            "c",
            "d",
        ]
    ) -> HatsSnapshot {
        var snapshot = HatsSnapshot()
        snapshot.settings.autoSwitch = createArmed(order)
        snapshot.rows = hats.map {
            HatRowState(
                hat: $0,
                isWearing: $0.id == wearing,
                usage: readings[$0.id],
                usageTrouble: nil,
                now: now,
                timeZone: utc
            )
        }

        return snapshot
    }

    private func createMissed(_ count: Int) -> MissedPolls {
        var missed = MissedPolls().settled(
            wearing: "a",
            fresh: [
                "a",
            ],
            from: .timer,
            every: 300,
            at: now.addingTimeInterval(-300 * Double(count))
        )
        for step in 0..<count {
            missed = missed.settled(
                wearing: "a",
                fresh: [],
                from: .timer,
                every: 300,
                at: now.addingTimeInterval(-300 * Double(count - step - 1))
            )
        }

        return missed
    }

    private func getSeen(
        _ hats: [Account],
        wearing: String = "a",
        readings: [String: UsageReading],
        order: [String] = [
            "b",
            "c",
            "d",
        ],
        missedPolls: Int = 0,
        fresh: Set<String>? = nil
    ) -> Seen {
        let snapshot = createSnapshot(
            hats,
            wearing: wearing,
            readings: readings,
            order: order
        )
        let world = AutoSwitchWorld.of(
            snapshot: snapshot,
            readings: readings,
            missed: createMissed(missedPolls),
            fresh: fresh ?? Set(readings.keys),
            from: .aPollLanded
        )
        let policy = snapshot.settings.autoSwitch
        let outcome = AutoSwitchEngine.outcome(
            policy: policy,
            world: world,
            now: now
        )
        let holding = AutoSwitchEngine.reasonForHolding(
            policy: policy,
            world: world,
            at: now
        )
        let warning = AutoSwitchWarning.of(
            decision: outcome.decision,
            holding: holding,
            blindness: world.blindness,
            onVacation: world.onVacation
        )
        var shown = snapshot
        shown.autoSwitchWarning = warning

        return Seen(
            outcome: outcome,
            holding: holding,
            warning: warning,
            snapshot: shown
        )
    }

    private func getJournalReason(_ seen: Seen) throws -> String {
        NowhereToGoLine.of(try XCTUnwrap(seen.outcome.decision.deadEnd, "no dead end was reached")).reason
    }

    private func getBody(_ seen: Seen) throws -> String {
        try XCTUnwrap(seen.warning).text(
            hat: "A",
            now: now,
            timeZone: utc
        ).1
    }

    func testAHatOnVacationIsNotChosenEvenWithRoomAndFirstInTheOrder() {
        let seen = getSeen(
            [
                createHat("a"),
                createHat("b", away: true),
                createHat("c"),
            ],
            readings: [
                "a": createReading(95),
                "b": createReading(5),
                "c": createReading(5),
            ]
        )

        XCTAssertEqual(
            seen.outcome.wearsHat,
            "c",
            "B is first in the order and has room, and it is the one hat the person told the switch "
                + "to leave alone"
        )
    }

    func testAnUnmeasuredHatOnVacationIsNotTheLastResortEither() {
        let orders: [[String]] = [
            [
                "b",
                "c",
            ],
            [],
        ]
        for order in orders {
            let seen = getSeen(
                [
                    createHat("a"),
                    createHat("b", away: true),
                    createHat("c"),
                ],
                readings: [
                    "a": createReading(95),
                ],
                order: order
            )

            XCTAssertEqual(
                seen.outcome.wearsHat,
                "c",
                "with no reading anywhere the first unmeasured hat is tried, and B is first whether "
                    + "the order names it or not (order \(order))"
            )
        }
    }

    func testWhenEveryOtherHatIsOnVacationTheDeadEndSaysSoAndNamesIt() throws {
        let seen = getSeen(
            [
                createHat("a"),
                createHat("b", away: true),
            ],
            readings: [
                "a": createReading(95),
                "b": createReading(5),
            ]
        )
        let named = "A reached its 5-hour limit, and B is on vacation. End the vacation in Settings → Hats."

        XCTAssertNil(seen.outcome.wearsHat)
        XCTAssertEqual(
            seen.outcome.decision,
            .nowhereToGo(.atALimit(
                .session,
                .othersAreOnVacation([
                    awayB,
                ])
            ))
        )
        XCTAssertEqual(
            try getBody(seen),
            named,
            "\"there is no other hat\" would be false - B is right there - and the way out is one "
                + "checkbox away"
        )
        XCTAssertEqual(seen.snapshot.deadEndBanner(now: now, timeZone: utc)?.line, named)
        XCTAssertEqual(try getJournalReason(seen), "othersAreOnVacation")

        let many = getSeen(
            [
                createHat("a"),
                createHat("b", away: true),
                createHat("c", away: true),
            ],
            readings: [
                "a": createReading(95),
            ]
        )
        XCTAssertEqual(
            try getBody(many),
            "A reached its 5-hour limit, and the other hats are on vacation. End a vacation in Settings → Hats."
        )
    }

    func testAMixedDeadEndSaysTheOthersAreSpentAndNamesTheOnesOnVacation() throws {
        let seen = getSeen(
            [
                createHat("a"),
                createHat("b"),
                createHat("c", away: true),
            ],
            readings: [
                "a": createReading(95),
                "b": createReading(97),
                "c": createReading(5),
            ]
        )

        XCTAssertEqual(try getJournalReason(seen), "othersAreSpent")
        XCTAssertEqual(
            try getBody(seen),
            "A reached its 5-hour limit, and no other hat has room; C is on vacation. Something frees up "
                + "at 09:00, or sooner if you reset a limit."
        )

        let two = getSeen(
            [
                createHat("a"),
                createHat("b"),
                createHat("c", away: true),
                createHat("d", away: true),
            ],
            readings: [
                "a": createReadingWithoutAReset(95),
                "b": createReadingWithoutAReset(97),
            ]
        )
        XCTAssertEqual(
            try getBody(two),
            "A reached its 5-hour limit, and no other hat has room; C and D are on vacation."
        )
    }

    func testAHatOnVacationThatNeedsALoginIsNotOfferedForSigningInAndLightsNoDot() throws {
        var expired = createHat("b", away: true)
        expired.refreshExpiresAt = now.addingTimeInterval(-60)
        let seen = getSeen(
            [
                createHat("a"),
                expired,
            ],
            readings: [
                "a": createReading(95),
                "b": createReading(5),
            ]
        )

        XCTAssertEqual(
            seen.outcome.decision,
            .nowhereToGo(.atALimit(
                .session,
                .othersAreOnVacation([
                    awayB,
                ])
            )),
            "B has room and needs a login, and it is on vacation: the vacation is the reason the switch "
                + "does not go there, not the login"
        )
        XCTAssertNil(
            seen.snapshot.deadEndBanner(now: now, timeZone: utc)?.signInTo,
            "so the banner offers no login button for it"
        )
        XCTAssertFalse(
            seen.snapshot.hasABlockedHatInPlay,
            "and the attention dot does not light for a hat the switch is not using"
        )
        XCTAssertEqual(
            seen.snapshot.rows.last?.blocker,
            "login expired",
            "the hat's own row still shows the problem, as it always did"
        )
    }

    func testAnotherHatThatNeedsALoginIsStillOfferedNextToOneOnVacation() throws {
        let seen = getSeen(
            [
                createHat("a"),
                createHat("b", away: true),
                createNeverSignedIn("c"),
            ],
            readings: [
                "a": createReading(95),
                "c": createReading(5),
            ]
        )

        XCTAssertEqual(try getBody(seen), "A reached its 5-hour limit, and C has room but needs login.")
        XCTAssertEqual(seen.snapshot.deadEndBanner(now: now, timeZone: utc)?.signInTo?.id, "c")
        XCTAssertTrue(seen.snapshot.hasABlockedHatInPlay)
    }

    func testWithTheUsageUnreadableAndEveryOtherHatOnVacationItDoesNotPromiseASwitch() throws {
        let hats = [
            createHat("a"),
            createHat("b", away: true),
        ]
        let readings = [
            "a": createReading(85),
            "b": createReading(5),
        ]
        let freshB: Set<String> = [
            "b",
        ]
        let second = getSeen(
            hats,
            readings: readings,
            missedPolls: 2,
            fresh: freshB
        )

        XCTAssertEqual(
            second.outcome.decision,
            .nowhereToGo(.unreadableAndOthersAreOnVacation([
                awayB,
            ]))
        )
        XCTAssertEqual(
            try getBody(second),
            "Hats can't read A's usage, and B is on vacation. End the vacation in Settings → Hats."
        )
        XCTAssertEqual(try getJournalReason(second), "othersAreOnVacation")
        XCTAssertEqual(try XCTUnwrap(second.outcome.decision.deadEnd).journalLimit, "usageCouldNotBeRead")

        let first = getSeen(
            hats,
            readings: readings,
            missedPolls: 1,
            fresh: freshB
        )
        XCTAssertEqual(
            first.outcome.decision,
            .hold,
            "the dead end is written from the second miss, as before"
        )
        XCTAssertEqual(first.holding, .blindAndOthersAreOnVacation)
        XCTAssertEqual(first.holding?.rawValue, "blindAndOthersAreOnVacation")
        XCTAssertEqual(first.holding?.isWorthAJournalLine, true)
        let said = try getBody(first)
        XCTAssertFalse(
            said.contains("as soon as it can"),
            "with every other hat on vacation there is nothing to switch to, so the promise would be "
                + "broken the moment it was made"
        )
        XCTAssertEqual(said, try getBody(second))
        XCTAssertTrue(
            AutoSwitchWarning.isTheSameEpisode(first.warning, as: second.warning),
            "the second miss says what the first one already said, so nobody is told twice"
        )
    }

    func testAWornHatThatNeedsALoginDoesNotStopTheVacationSentenceWhenTheUsageIsUnreadable() throws {
        var expired = createHat("a")
        expired.refreshExpiresAt = now.addingTimeInterval(-60)
        let hats = [
            expired,
            createHat("b", away: true),
        ]
        let readings = [
            "a": createReading(85),
        ]

        let first = getSeen(
            hats,
            readings: readings,
            missedPolls: 1,
            fresh: []
        )
        let second = getSeen(
            hats,
            readings: readings,
            missedPolls: 2,
            fresh: []
        )

        XCTAssertEqual(
            first.holding,
            .blindAndOthersAreOnVacation,
            "the worn hat is in the list of hats that need a login, and it is the one being worn, "
                + "not another hat the person could sign in to instead"
        )
        XCTAssertEqual(
            second.outcome.decision,
            .nowhereToGo(.unreadableAndOthersAreOnVacation([
                awayB,
            ]))
        )
    }

    func testWithTheUsageUnreadableAndTheOthersSpentTheSentenceNamesTheHatOnVacation() throws {
        let fresh: Set<String> = [
            "b",
            "c",
        ]
        let seen = getSeen(
            [
                createHat("a"),
                createHat("b"),
                createHat("c", away: true),
            ],
            readings: [
                "a": createReading(85),
                "b": createReadingOfBothWindows(95),
                "c": createReadingOfBothWindows(5),
            ],
            missedPolls: 2,
            fresh: fresh
        )
        let warning = try XCTUnwrap(seen.warning)
        let text = warning.text(
            hat: "A",
            now: now,
            timeZone: utc
        )

        XCTAssertEqual(seen.holding, .blindTargetSpent)
        XCTAssertEqual(text.0, "Can't read usage")
        XCTAssertEqual(
            text.1,
            "Hats can't read A's usage, and the other hats are spent; C is on vacation.",
            "the dead-end sentences name the hat on vacation, so the person knows where the room is"
        )
        XCTAssertEqual(warning.menuBarLabel, HatsCopy.theWornUsageCannotBeReadAloud)

        let nobodyAway = getSeen(
            [
                createHat("a"),
                createHat("b"),
            ],
            readings: [
                "a": createReading(85),
                "b": createReadingOfBothWindows(95),
            ],
            missedPolls: 2,
            fresh: fresh
        )
        XCTAssertEqual(try getBody(nobodyAway), "Hats can't read A's usage, and the other hats are spent.")
    }

    func testWithTheUsageUnreadableAHatWithRoomIsStillWornPastOneOnVacation() {
        let seen = getSeen(
            [
                createHat("a"),
                createHat("b", away: true),
                createHat("c"),
            ],
            readings: [
                "a": createReading(85),
                "b": createReadingOfBothWindows(5),
                "c": createReadingOfBothWindows(5),
            ],
            missedPolls: 2,
            fresh: [
                "b",
                "c",
            ]
        )

        XCTAssertEqual(
            seen.outcome.wearsHat,
            "c",
            "both of C's windows were read in this poll and are far from the thresholds; B was too and "
                + "comes first in the order, and it stays on vacation"
        )
        XCTAssertEqual(seen.outcome.record?.cause, .usageCouldNotBeRead)
    }

    func testWithTheUsageUnreadableAHatThatNeedsALoginIsNotCalledAVacation() {
        let seen = getSeen(
            [
                createHat("a"),
                createNeverSignedIn("b"),
                createHat("c", away: true),
            ],
            readings: [
                "a": createReading(85),
            ],
            missedPolls: 2,
            fresh: []
        )

        XCTAssertEqual(
            seen.outcome.decision,
            .nowhereToGo(.noFreshReading),
            "B is not on vacation, so \"the other hats are on vacation\" would be false; the older "
                + "sentence about fresh readings still holds"
        )
    }

    func testAVacationEpisodeIsTheSentenceThePersonReads() {
        let createUnreadable = { (away: [HatOnVacation]) in
            AutoSwitchWarning.unreadableAndOthersAreOnVacation(away)
        }
        let createAtALimit = { (by: AutoSwitchDeadEnd.StrandedBy) in
            AutoSwitchWarning.nowhereToGoAtALimit(.session, by)
        }
        let two = [
            awayB,
            awayC,
        ]
        let three = [
            awayB,
            awayC,
            awayD,
        ]
        let onlyB = [
            awayB,
        ]
        let onlyC = [
            awayC,
        ]
        let cAndD = [
            awayC,
            awayD,
        ]

        XCTAssertTrue(
            AutoSwitchWarning.isTheSameEpisode(createUnreadable(two), as: createUnreadable(three)),
            "two hats on vacation and three read the same sentence, so a third one leaving does not "
                + "wake the person again"
        )
        XCTAssertFalse(
            AutoSwitchWarning.isTheSameEpisode(createUnreadable(onlyB), as: createUnreadable(onlyC)),
            "but a different name is a different sentence"
        )
        XCTAssertTrue(
            AutoSwitchWarning.isTheSameEpisode(
                createAtALimit(.othersAreOnVacation(two)),
                as: createAtALimit(.othersAreOnVacation(three))
            )
        )
        XCTAssertFalse(
            AutoSwitchWarning.isTheSameEpisode(
                createAtALimit(.othersAreOnVacation(onlyB)),
                as: createAtALimit(.othersAreOnVacation(onlyC))
            )
        )
        XCTAssertTrue(
            AutoSwitchWarning.isTheSameEpisode(
                createAtALimit(.othersAreSpentOrOnVacation(freesUpAt: resetsAt, onVacation: onlyC)),
                as: createAtALimit(.othersAreSpentOrOnVacation(freesUpAt: sooner, onVacation: onlyC))
            ),
            "the hour moving is not a new fact, as for a plain spent dead end"
        )
        XCTAssertFalse(
            AutoSwitchWarning.isTheSameEpisode(
                createAtALimit(.othersAreSpentOrOnVacation(freesUpAt: resetsAt, onVacation: onlyC)),
                as: createAtALimit(.othersAreSpentOrOnVacation(freesUpAt: resetsAt, onVacation: cAndD))
            ),
            "the mixed sentence names every hat on vacation, so another name is a new sentence"
        )
        XCTAssertEqual(HatsCopy.getAlsoOnVacation(three), "B, C and D are on vacation")
        XCTAssertEqual(
            NowhereToGoLine.of(.atALimit(.session, .othersAreOnVacation(onlyB))).key,
            NowhereToGoLine.of(.atALimit(.session, .othersAreOnVacation(onlyC))).key,
            "the journal is keyed on the reason, not on the names"
        )
    }

    func testAWornHatOnVacationIsLeftAtItsLimitLikeAnyOther() {
        let seen = getSeen(
            [
                createHat("a", away: true),
                createHat("b"),
            ],
            readings: [
                "a": createReading(95),
                "b": createReading(5),
            ]
        )

        XCTAssertEqual(seen.outcome.wearsHat, "b")
    }

    func testAWornHatOnVacationThatCannotBeWornDoesNotNameItsOwnResetAsTheWayBack() throws {
        var revoked = createHat("a", away: true)
        revoked.lastLoginAt = now.addingTimeInterval(-7200)
        revoked.authRefusedAt = now.addingTimeInterval(-60)
        let seen = getSeen(
            [
                revoked,
                createHat("b"),
            ],
            readings: [
                "a": createReading(95, resets: sooner),
                "b": createReading(97),
            ]
        )

        XCTAssertEqual(
            try getBody(seen),
            "A reached its 5-hour limit, and no other hat has room. Something frees up at 09:00, or "
                + "sooner if you reset a limit.",
            "the worn hat is on vacation only for the switch once it comes off; while it is on, its "
                + "refused login keeps it out of the hour, as it did before"
        )
    }

    func testTheOnlyHatOnVacationAndWornIsStillTheOnlyHat() throws {
        let seen = getSeen(
            [
                createHat("a", away: true),
            ],
            readings: [
                "a": createReading(95),
            ]
        )

        XCTAssertEqual(seen.outcome.decision, .nowhereToGo(.atALimit(.session, .noOtherHat)))
        XCTAssertEqual(try getBody(seen), "A reached its 5-hour limit. There is no other hat to switch to.")
    }

    func testTheNextLineSkipsAHatOnVacation() throws {
        let seen = getSeen(
            [
                createHat("a"),
                createHat("b", away: true),
                createHat("c"),
            ],
            readings: [
                "a": createReading(10),
                "b": createReading(5),
                "c": createReading(5),
            ]
        )

        XCTAssertEqual(seen.snapshot.nextInLine, "c")
        XCTAssertEqual(seen.snapshot.getHandover(for: try XCTUnwrap(seen.snapshot.wearing)), "next: C")
    }

    func testWithEveryOtherHatOnVacationTheNextLineSaysSoRatherThanNothing() throws {
        let away = getSeen(
            [
                createHat("a"),
                createHat("b", away: true),
                createHat("c", away: true),
            ],
            readings: [
                "a": createReading(10),
            ]
        )

        XCTAssertNil(away.snapshot.nextInLine)
        XCTAssertTrue(away.snapshot.isEveryOtherHatOnVacation)
        XCTAssertEqual(
            away.snapshot.getHandover(for: try XCTUnwrap(away.snapshot.wearing)),
            "next: none, the others are on vacation",
            "the line the worn row shows, read through the same function the menu calls"
        )
        XCTAssertNil(
            away.snapshot.getHandover(for: try XCTUnwrap(away.snapshot.rows.last)),
            "a hat that is not worn has no next line"
        )

        let partly = getSeen(
            [
                createHat("a"),
                createHat("b", away: true),
                createNeverSignedIn("c"),
            ],
            readings: [
                "a": createReading(10),
            ]
        )
        XCTAssertFalse(
            partly.snapshot.isEveryOtherHatOnVacation,
            "C is not on vacation, it needs a login, so the line stays as it was"
        )
        XCTAssertNil(partly.snapshot.getHandover(for: try XCTUnwrap(partly.snapshot.wearing)))
        let alone = getSeen(
            [
                createHat("a"),
            ],
            readings: [:]
        )
        XCTAssertFalse(
            alone.snapshot.isEveryOtherHatOnVacation,
            "and a single hat has no others to be on vacation"
        )
    }

    func testAVacationIsNotALoginBlocker() {
        let away = HatRowState(
            hat: createHat("b", away: true),
            isWearing: false,
            usage: nil,
            usageTrouble: nil,
            now: now
        )
        XCTAssertNil(away.blocker)
        XCTAssertTrue(
            away.isSwitchable,
            "the row is still worn on a click: a vacation keeps the switch away, not the person"
        )
        XCTAssertTrue(createHat("b", away: true).isSwitchable)
        XCTAssertNil(createHat("b", away: true).blocker(at: now))

        let shutOut = createNeverSignedIn("c")
        var shutOutAndAway = shutOut
        shutOutAndAway.vacationSince = now
        XCTAssertEqual(shutOutAndAway.blocker(at: now), shutOut.blocker(at: now))
        XCTAssertEqual(shutOutAndAway.isSwitchable, shutOut.isSwitchable)
        let row = HatRowState(
            hat: shutOutAndAway,
            isWearing: false,
            usage: nil,
            usageTrouble: nil,
            now: now
        )
        XCTAssertEqual(row.blocker, "needs login")
        XCTAssertFalse(row.isSwitchable)
    }

    func testAHatBackFromVacationIsChosenAgainFromItsOldPlace() {
        let readings = [
            "a": createReading(95),
            "b": createReading(5),
            "c": createReading(5),
        ]
        var returned = createHat("b", away: true)
        let before = getSeen(
            [
                createHat("a"),
                returned,
                createHat("c"),
            ],
            readings: readings
        )
        XCTAssertEqual(before.outcome.wearsHat, "c")

        returned.vacationSince = nil
        let after = getSeen(
            [
                createHat("a"),
                returned,
                createHat("c"),
            ],
            readings: readings
        )

        XCTAssertEqual(
            after.outcome.wearsHat,
            "b",
            "the order was never touched, so B is first again"
        )
    }

    func testAWarningNamingAHatToSignIntoGoesAwayWhenThatHatGoesOnVacation() {
        let named = AutoSwitchWarning.nowhereToGoAtALimit(
            .session,
            .othersNeedSigningIn(
                ShutOutHat(
                    id: "c",
                    title: "C",
                    blocker: "needs login",
                    loginAction: "Log in…"
                ),
                alsoShutOut: []
            )
        )
        var snapshot = createSnapshot(
            [
                createHat("a"),
                createHat("c", away: true),
            ],
            readings: [:]
        )
        snapshot.autoSwitchWarning = named

        XCTAssertNil(
            snapshot.warningAboutTheWornHat,
            "the banner would offer a login for a hat the switch is no longer going to use"
        )
        XCTAssertNil(snapshot.deadEndBanner(now: now, timeZone: utc))
    }

    func testAWarningNamingAHatOnVacationLastsOnlyWhileThatHatIsAway() {
        let onlyB = [
            awayB,
        ]
        let warnings: [AutoSwitchWarning] = [
            .nowhereToGoAtALimit(.session, .othersAreOnVacation(onlyB)),
            .nowhereToGoAtALimit(.session, .othersAreSpentOrOnVacation(freesUpAt: resetsAt, onVacation: onlyB)),
            .unreadableAndOthersAreOnVacation(onlyB),
            .everyOtherHatIsSpentOrOnVacation(onlyB),
        ]
        let stillAway = createSnapshot(
            [
                createHat("a"),
                createHat("b", away: true),
            ],
            readings: [:]
        )
        let back = createSnapshot(
            [
                createHat("a"),
                createHat("b"),
            ],
            readings: [:]
        )
        let removed = createSnapshot(
            [
                createHat("a"),
            ],
            readings: [:]
        )
        let oneMoreAway = createSnapshot(
            [
                createHat("a"),
                createHat("b", away: true),
                createHat("c", away: true),
            ],
            readings: [:]
        )

        for warning in warnings {
            XCTAssertTrue(
                stillAway.hasOnlyHatsThatAreStillHere(warning),
                "B is still away, so \(warning) is still the truth"
            )
            XCTAssertFalse(
                back.hasOnlyHatsThatAreStillHere(warning),
                "B came back, and until the next poll lands \(warning) would say it is away"
            )
            XCTAssertFalse(
                removed.hasOnlyHatsThatAreStillHere(warning),
                "B was removed, and a sentence naming a hat that is gone is worse than none (\(warning))"
            )
            XCTAssertFalse(
                oneMoreAway.hasOnlyHatsThatAreStillHere(warning),
                "C went on vacation too, and until the next poll lands \(warning) would leave it out"
            )
        }
        var shown = back
        shown.autoSwitchWarning = warnings.first
        XCTAssertNil(shown.warningAboutTheWornHat)
        XCTAssertNil(shown.deadEndBanner(now: now, timeZone: utc))
    }

    func testAnOldAccountsFileWithoutTheFieldReadsAsNobodyOnVacation() throws {
        let old: [String: Any] = [
            "accounts": [
                [
                    "id": "a",
                    "email": "a@x.co",
                    "hasStoredCredentials": true,
                ],
            ],
            "activeID": "a",
        ]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let contents = try decoder.decode(AccountsFile.Contents.self, from: JSONSerialization.data(withJSONObject: old))

        XCTAssertNil(
            contents.accounts.first?.vacationSince,
            "a Bool with a default would have thrown here and taken the whole file down as unreadable"
        )
    }

    private func createIsolatedStore() throws -> AccountStore {
        let override = ProcessInfo.processInfo.environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(
            override.isEmpty,
            "the store writes accounts.json through StateDirectory, and without HATS_STATE_HOME that is "
                + "the developer's own list of hats"
        )

        return AccountStore(osAccount: "vacation-test", keychain: FakeKeychain().world())
    }

    private func getReloaded(_ id: String) throws -> Account {
        let store = AccountStore(osAccount: "vacation-test", keychain: FakeKeychain().world())

        return try XCTUnwrap(store.accounts.first { $0.id == id })
    }

    func testTheMarkSurvivesARestartAndComesOffAgain() throws {
        let store = try createIsolatedStore()
        let worn = try store.add(email: "vacation-\(UUID().uuidString.prefix(8))@b.com", browser: nil)
        try store.noteActivated(worn.id, target: worn)
        let since = Date(timeIntervalSince1970: 1_800_000_000)

        try store.setVacation(
            worn.id,
            on: true,
            at: since
        )

        XCTAssertEqual(
            try getReloaded(worn.id).vacationSince,
            since,
            "compared on the field: Account's == looks at the id alone"
        )
        XCTAssertEqual(
            store.activeID,
            worn.id,
            "the worn hat stays on when it goes on vacation"
        )

        try store.setVacation(
            worn.id,
            on: true,
            at: since.addingTimeInterval(3600)
        )
        XCTAssertEqual(
            try getReloaded(worn.id).vacationSince,
            since,
            "asking for the state it is already in changes nothing, the start date included"
        )

        try store.setVacation(
            worn.id,
            on: false,
            at: since.addingTimeInterval(7200)
        )
        XCTAssertNil(try getReloaded(worn.id).vacationSince)
    }

    func testAFailedWriteLeavesNoMarkInMemory() throws {
        let store = try createIsolatedStore()
        let parked = try store.add(email: "vacation-\(UUID().uuidString.prefix(8))@b.com", browser: nil)
        let folder = StateDirectory.url.path
        let permissions = try FileManager.default.attributesOfItem(atPath: folder)[.posixPermissions]
        let readOnly: [FileAttributeKey: Any] = [
            .posixPermissions: 0o500,
        ]
        let restored: [FileAttributeKey: Any] = [
            .posixPermissions: permissions ?? 0o700,
        ]
        try FileManager.default.setAttributes(readOnly, ofItemAtPath: folder)

        XCTAssertThrowsError(try store.setVacation(
            parked.id,
            on: true,
            at: now
        ))

        try FileManager.default.setAttributes(restored, ofItemAtPath: folder)
        XCTAssertNil(
            store.accounts.first { $0.id == parked.id }?.vacationSince,
            "the change is rolled back in memory, so the checkbox does not show a mark the file does "
                + "not have"
        )
        XCTAssertFalse(
            store.hasUnsavedChanges,
            "and nothing is left pending for the next unrelated save to write after all"
        )
        XCTAssertNil(try getReloaded(parked.id).vacationSince)
    }

    private func getSource(_ name: String) -> String {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/\(name)")

        return (try? String(contentsOf: source, encoding: .utf8)) ?? ""
    }

    private func getText(
        of function: String,
        in text: String,
        until next: String
    ) throws -> String {
        let start = try XCTUnwrap(text.range(of: function)).lowerBound
        let rest = text[start...]
        let end = rest.dropFirst().range(of: next)?.lowerBound ?? rest.endIndex

        return String(rest[..<end])
    }

    func testTheJournalLineIsWrittenOnlyAfterTheFileWasSaved() throws {
        let setting = try getText(
            of: "func setVacation(",
            in: getSource("AccountStore.swift"),
            until: "\n    }\n"
        )
        let saved = try XCTUnwrap(setting.range(of: "try persist(orRestore: before)")).lowerBound
        let logged = try XCTUnwrap(setting.range(of: "Journal.log(\"hat.vacation\"")).lowerBound

        XCTAssertLessThan(
            saved,
            logged,
            "a failed write throws out of the function before the line, so the journal never reports a "
                + "vacation the file does not hold"
        )
    }

    func testChangingAVacationAsksForAPollRightAwayAndSaysWhenItCouldNotSave() throws {
        let actions = getSource("AppDelegate+Actions.swift")
        let setting = try getText(
            of: "func setVacation(",
            in: actions,
            until: "\n    }\n"
        )

        XCTAssertTrue(
            setting.contains("usage.poll("),
            "the warning and the next line are recomputed only when a poll lands, so without this a "
                + "stale dead end stays up for five minutes"
        )
        XCTAssertTrue(setting.contains("HatDialogs.present(error, title: \"Could not save that change\")"))
        XCTAssertLessThan(
            try XCTUnwrap(actions.range(of: "func setVacation(")).lowerBound,
            try XCTUnwrap(actions.range(of: "func remove(")).lowerBound,
            "above remove, so the test that reads remove's poll from there to the end of the file "
                + "cannot be satisfied by this one"
        )
        XCTAssertTrue(
            getSource("AppDelegate+Redraw.swift").contains("anyHatBlocked: snapshot.hasABlockedHatInPlay"),
            "the dot is drawn from the same list the dead end reads"
        )
    }

    func testTheWarningIsHandedTheHatsOnVacationOfTheWorldItWasDecidedIn() throws {
        let warned = try getText(
            of: "AutoSwitchWarning.of(",
            in: getSource("AppDelegate+AutoSwitch.swift"),
            until: "\n            )"
        )

        XCTAssertTrue(
            warned.contains("onVacation: world.onVacation"),
            "an empty list here drops the name from the first-miss warning, and the second miss, which "
                + "carries the name, then reads as a new episode and notifies again"
        )
    }
}

private extension AutoSwitchDecision {
    var deadEnd: AutoSwitchDeadEnd? {
        guard case .nowhereToGo(let deadEnd) = self else { return nil }

        return deadEnd
    }
}
