import XCTest
@testable import Hats

final class NowhereToGoWarningTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let resetsAt = Date(timeIntervalSince1970: 1_800_003_600)
    private let sooner = Date(timeIntervalSince1970: 1_800_001_800)
    private let utc = TimeZone(identifier: "UTC")!

    private var armed: AutoSwitchPolicy {
        var policy = AutoSwitchPolicy()
        policy.isOn = true
        policy.order = ["personal", "team"]
        return policy
    }

    private func blind(
        _ missedPolls: Int = 0,
        fresh: Set<String> = ["work", "personal", "team"],
        landed: Bool = true
    ) -> UsageBlindness {
        UsageBlindness(missedPolls: missedPolls, hasReadTheWornHatSinceItWentOn: true,
                       fresh: fresh, landedAPoll: landed)
    }

    private func spent(session: Int = 100, weekly: Int? = nil, resets: Date?) -> UsageReading {
        UsageReading(
            session: UsageWindow(used: session, limit: 100, resetsAt: resets),
            weekly: weekly.map { UsageWindow(used: $0, limit: 100, resetsAt: resets) }
        )
    }

    private func shutOut(_ id: String, _ blocker: String = "needs login") -> ShutOutHat {
        ShutOutHat(id: id, title: id.capitalized, blocker: blocker, loginAction: "Log in again…")
    }

    private func world(
        _ readings: [String: UsageReading],
        eligible: [String],
        blocked: [ShutOutHat] = [],
        blindness: UsageBlindness? = nil
    ) -> AutoSwitchWorld {
        AutoSwitchWorld(readings: readings, wearing: "work", eligible: eligible,
                        blocked: blocked, blindness: blindness ?? blind())
    }

    private func theDayItWentQuiet(resets: Date?, room: Int = 95) -> AutoSwitchWorld {
        world(["work": spent(resets: resets),
               "personal": UsageReading(session: nil,
                                        weekly: UsageWindow(used: room, limit: 100, resetsAt: nil))],
              eligible: ["work", "personal"])
    }

    private func decision(in world: AutoSwitchWorld, policy: AutoSwitchPolicy? = nil) -> AutoSwitchDecision {
        AutoSwitchEngine.outcome(policy: policy ?? armed, world: world, now: now).decision
    }

    private func warning(in world: AutoSwitchWorld, policy: AutoSwitchPolicy? = nil) -> AutoSwitchWarning? {
        let policy = policy ?? armed
        let outcome = AutoSwitchEngine.outcome(policy: policy, world: world, now: now)
        let holding = AutoSwitchEngine.reasonForHolding(policy: policy, world: world, at: now)

        return AutoSwitchWarning.of(decision: outcome.decision, holding: holding,
                                    blindness: world.blindness)
    }

    private func body(of warning: AutoSwitchWarning?) throws -> String {
        try XCTUnwrap(warning).text(hat: "Work", now: now, timeZone: utc).1
    }

    private func spentAt(_ freesUpAt: Date?) -> AutoSwitchDecision {
        .nowhereToGo(.atALimit(.session, .othersAreSpent(freesUpAt: freesUpAt)))
    }

    func testTheCircumstancesOf25SeptemberNowReachThePersonInsteadOfOnlyTheJournal() throws {
        let stranded = theDayItWentQuiet(resets: resetsAt)
        XCTAssertEqual(decision(in: stranded), spentAt(resetsAt),
                       "the worn hat had taken its five-hour window whole and the only other hat "
                           + "sat on weekly=95/100 against a weekly threshold of 95, so refusing "
                           + "to move was the right answer - the defect was that it was silent")
        let raised = try XCTUnwrap(warning(in: stranded),
                                   "measured on the live 0.2.2: an hour of autoSwitch.nowhereToGo "
                                       + "every five minutes, no dot and no notification, and the "
                                       + "person learned of it by hitting the limit")
        XCTAssertEqual(try body(of: raised),
                       "Work reached its 5-hour limit, and no other hat has room. Something frees "
                           + "up at 09:00, or sooner if you reset a limit.")
    }

    func testTheThreeDeadEndsAreToldApartBecauseTwoOfThemThePersonCanFix() throws {
        let alone = world(["work": spent(resets: resetsAt)], eligible: ["work"])
        XCTAssertEqual(decision(in: alone), .nowhereToGo(.atALimit(.session, .noOtherHat)))
        XCTAssertEqual(try body(of: warning(in: alone)),
                       "Work reached its 5-hour limit. There is no other hat to switch to.",
                       "one hat is not \"no other hat has room\": there is no other hat at all, "
                           + "and telling somebody the others are full when they have none reads "
                           + "as a suggestion to wait for something that does not exist")

        let needsSigningIn = world(["work": spent(resets: resetsAt)],
                                   eligible: ["work"], blocked: [shutOut("personal")])
        XCTAssertEqual(try body(of: warning(in: needsSigningIn)),
                       "Work reached its 5-hour limit, and Personal has room but needs login.",
                       "a hat that needs signing in HAS room - eligible is filtered by isSwitchable "
                           + "before any usage is counted, so the policy never saw it and the app "
                           + "told the person to wait for room it already had")

        let spentOthers = world(["work": spent(resets: resetsAt), "personal": spent(resets: sooner)],
                                eligible: ["work", "personal"])
        XCTAssertEqual(decision(in: spentOthers), spentAt(sooner))
    }

    func testTheBlockersOwnWordsAreQuotedRatherThanOnePhraseForAllFive() throws {
        let disagreeing = world(["work": spent(resets: resetsAt)], eligible: ["work"],
                                blocked: [shutOut("personal", "accounts disagree")])
        XCTAssertEqual(try body(of: warning(in: disagreeing)),
                       "Work reached its 5-hour limit, and Personal has room but accounts disagree.",
                       "five blockers reach this sentence and signing in fixes only some of them - "
                           + "for a hat whose accounts disagree a login is not the remedy at all, "
                           + "and for one never logged into there is no \"again\". HatsCopy.blocker "
                           + "already writes all five apart, so the sentence quotes it")
        let expired = world(["work": spent(resets: resetsAt)], eligible: ["work"],
                            blocked: [shutOut("personal", "login expired")])
        XCTAssertEqual(try body(of: warning(in: expired)),
                       "Work reached its 5-hour limit, and Personal has room but login expired.")
    }

    func testAMixedDeadEndNamesTheHalfThePersonCanActOnNow() throws {
        let mixed = world(["work": spent(resets: resetsAt), "personal": spent(resets: sooner)],
                          eligible: ["work", "personal"], blocked: [shutOut("team")])
        XCTAssertEqual(decision(in: mixed),
                       .nowhereToGo(.atALimit(.session, .othersNeedSigningIn(shutOut("team"),
                                                                            alsoShutOut: []))))
        XCTAssertEqual(try body(of: warning(in: mixed)),
                       "Work reached its 5-hour limit, and Team has room but needs login.",
                       "signing in is available now; waiting for a window is not, so the sentence "
                           + "names the door that opens rather than the one that opens later")
    }

    func testABlockedWornHatIsNotOfferedBackToThePersonAsSomewhereToGo() {
        let wornIsBlocked = world(["work": spent(resets: resetsAt)],
                                  eligible: [], blocked: [shutOut("work")])
        XCTAssertEqual(decision(in: wornIsBlocked), .nowhereToGo(.atALimit(.session, .noOtherHat)),
                       "a login can expire on the hat being worn, and then it is the worn hat that "
                           + "falls out of eligible - \"Work has room but needs login\" about the "
                           + "hat already on the head would be nonsense")
    }

    func testAWornHatThatIsItselfShutOutDoesNotCountAsSomethingThatFreesUp() {
        let wornShutOutTooAndSooner = world(
            ["work": spent(resets: sooner), "personal": spent(resets: resetsAt)],
            eligible: ["personal"], blocked: [shutOut("work")]
        )
        XCTAssertEqual(decision(in: wornShutOutTooAndSooner), spentAt(resetsAt),
                       "the worn hat's window opens first and opens onto nothing: it needs signing "
                           + "in before it can be worn, so counting it would name an hour at which "
                           + "the person still cannot work. Only hats the switch could actually "
                           + "move to count, and the worn hat is one of those only while it is "
                           + "wearable")
        let wornIsFine = world(["work": spent(resets: sooner), "personal": spent(resets: resetsAt)],
                               eligible: ["work", "personal"])
        XCTAssertEqual(decision(in: wornIsFine), spentAt(sooner),
                       "and when nothing is shut out, the worn hat coming back first is the person "
                           + "working again")
    }

    func testSeveralShutOutHatsLoseTheirNamesRatherThanBeingListed() throws {
        let many = world(["work": spent(resets: resetsAt)],
                         eligible: ["work"], blocked: [shutOut("personal"), shutOut("team")])
        XCTAssertEqual(try body(of: warning(in: many)),
                       "Work reached its 5-hour limit, and the other hats have room but none "
                           + "of them can be worn.",
                       "with more than one there is neither a single name to give nor a single "
                           + "blocker to quote, and the five blockers do not share a sentence")
    }

    func testAHatThatIsBothShutOutAndSpentIsNeverCalledRoomThePersonCanSignInTo() throws {
        let bothWrong = world(["work": spent(resets: resetsAt), "personal": spent(resets: sooner)],
                              eligible: ["work"], blocked: [shutOut("personal")])
        XCTAssertEqual(decision(in: bothWrong), spentAt(resetsAt),
                       "the hat needs signing in AND is over its own threshold, so \"has room but "
                           + "needs login\" would send the person to do a login that buys them "
                           + "nothing - eligible is filtered before any usage is counted, which is "
                           + "why the reason has to ask the readings itself")
        XCTAssertEqual(try body(of: warning(in: bothWrong)),
                       "Work reached its 5-hour limit, and no other hat has room. Something frees "
                           + "up at 09:00, or sooner if you reset a limit.",
                       "\"no other hat has room\" is true of it, and \"there is no other hat\" "
                           + "would not be - a hat that exists and is full belongs in the spent "
                           + "sentence, not in the one that says it does not exist")
        let alsoASpentEligible = world(["work": spent(resets: resetsAt),
                                        "personal": spent(resets: sooner),
                                        "team": spent(resets: resetsAt)],
                                       eligible: ["work", "team"], blocked: [shutOut("personal")])
        XCTAssertEqual(decision(in: alsoASpentEligible), spentAt(resetsAt),
                       "personal comes back half an hour earlier than anything else and is still "
                           + "not the answer: when that window rolls over the hat needs signing in "
                           + "before it can be worn, so nothing has freed up by itself")
    }

    func testAShutOutHatNobodyCouldMeasureIsStillOfferedAsSomethingToSignInTo() {
        let unmeasured = world(["work": spent(resets: resetsAt)],
                               eligible: ["work"], blocked: [shutOut("personal")])
        XCTAssertEqual(decision(in: unmeasured),
                       .nowhereToGo(.atALimit(.session, .othersNeedSigningIn(shutOut("personal"),
                                                                            alsoShutOut: []))),
                       "a hat that needs signing in often cannot be polled at all, so room unknown "
                           + "is the ordinary case rather than the rare one. Between two unproven "
                           + "sentences the one naming an action the person can take now beats the "
                           + "one telling them to wait - and nextHat already treats an unmeasured "
                           + "hat as worth trying rather than as spent")
    }

    func testAmongShutOutHatsOnlyTheOnesWithRoomAreNamed() throws {
        let some = world(["work": spent(resets: resetsAt), "personal": spent(resets: sooner)],
                         eligible: ["work"], blocked: [shutOut("personal"), shutOut("team")])
        XCTAssertEqual(decision(in: some),
                       .nowhereToGo(.atALimit(.session, .othersNeedSigningIn(shutOut("team"),
                                                                            alsoShutOut: []))),
                       "personal is shut out and full, team is shut out and unmeasured; naming "
                           + "both would send the person to sign in to one that cannot help")
        XCTAssertEqual(try body(of: warning(in: some)),
                       "Work reached its 5-hour limit, and Team has room but needs login.",
                       "one survivor, so it is named rather than being hidden behind \"the other "
                           + "hats\"")
    }

    func testTheHourNamedIsTheFirstMomentAnyHatFreesUpAndNotTheWornHatsOwnWindow() {
        let others = world(["work": spent(resets: resetsAt), "personal": spent(resets: sooner)],
                           eligible: ["work", "personal"])
        XCTAssertEqual(decision(in: others), spentAt(sooner),
                       "the question the sentence answers is \"when can I work again\", and the "
                           + "worn hat's own window answers a different one - here another hat "
                           + "comes back half an hour earlier, and naming the worn hat's reset "
                           + "would have sent the person away for twice as long as they needed")
    }

    func testAHatOverBothWindowsIsFreeOnlyWhenTheLaterOneComesBack() {
        var policy = armed
        policy.weeklyThresholdPercent = 95
        let overBoth = UsageReading(
            session: UsageWindow(used: 100, limit: 100, resetsAt: sooner),
            weekly: UsageWindow(used: 99, limit: 100, resetsAt: resetsAt)
        )
        XCTAssertEqual(decision(in: world(["work": spent(resets: sooner), "personal": overBoth],
                                          eligible: ["work", "personal"]), policy: policy),
                       spentAt(sooner),
                       "work frees up at the earlier time and personal not until its week resets, "
                           + "so the earliest of the two is work's - a hat over two windows is not "
                           + "free when the first of them rolls over")
        XCTAssertEqual(decision(in: world(["work": spent(resets: nil), "personal": overBoth],
                                          eligible: ["work", "personal"]), policy: policy),
                       spentAt(resetsAt),
                       "with the worn hat's reset unknown the answer is personal's later window, "
                           + "not its earlier one")
    }

    func testAHatOverTwoWindowsWithOnlyOneResetKnownNamesNoHourAtAll() {
        var policy = armed
        policy.weeklyThresholdPercent = 95
        let halfKnown = UsageReading(
            session: UsageWindow(used: 100, limit: 100, resetsAt: sooner),
            weekly: UsageWindow(used: 99, limit: 100, resetsAt: nil)
        )
        XCTAssertEqual(decision(in: world(["work": spent(resets: nil), "personal": halfKnown],
                                          eligible: ["work", "personal"]), policy: policy),
                       spentAt(nil),
                       "the hat frees up at the LATER of its two windows, and the later one is "
                           + "unknown - so the known hour is a lower bound, not the moment. Naming "
                           + "it would be wrong in the direction of \"sooner\", and at the named "
                           + "hour nothing would open, which is the worse of the two errors. The "
                           + "price of nil is that the person waits longer than they need to, and "
                           + "there is no better cure here")
    }

    func testAResetKnownForNobodySaysNothingRatherThanGuessing() throws {
        let unknown = world(["work": spent(resets: nil), "personal": spent(resets: nil)],
                            eligible: ["work", "personal"])
        XCTAssertEqual(decision(in: unknown), spentAt(nil))
        XCTAssertEqual(try body(of: warning(in: unknown)),
                       "Work reached its 5-hour limit, and no other hat has room.",
                       "no hour anywhere, so no hour is offered - and the reset hint goes with it, "
                           + "because it hangs off the hour")
        let partly = world(["work": spent(resets: nil), "personal": spent(resets: sooner)],
                           eligible: ["work", "personal"])
        XCTAssertEqual(decision(in: partly), spentAt(sooner),
                       "one known reset among several unknowns is still an answer")
    }

    func testAPollThatFindsSomewhereToGoWarnsAboutNothing() {
        let moving = theDayItWentQuiet(resets: resetsAt, room: 5)
        XCTAssertEqual(decision(in: moving), .fire(to: "personal", limit: .session, resetsAt: resetsAt))
        XCTAssertNil(warning(in: moving),
                     "the hat moves, and a warning next to a switch would contradict the switch")
    }

    func testTheBlindDeadEndKeepsItsOwnAnswer() {
        let stale = UsageReading(session: UsageWindow(used: 89, limit: 100, resetsAt: resetsAt),
                                 weekly: nil)
        let dark = world(["work": stale], eligible: ["work", "personal"],
                         blindness: blind(2, fresh: []))
        XCTAssertEqual(decision(in: dark), .nowhereToGo(.noFreshReading))
        XCTAssertEqual(warning(in: dark), .nowhereFreshToGo,
                       "nothing was measured here, so there is no limit to name and no window to "
                           + "come back - and the type now says so: a dead end is either blind or "
                           + "at a limit with a reason, and \"a limit with no reason\" cannot be "
                           + "built at all")
    }

    func testOnlyALandedPollRaisesIt() {
        let notAPoll = world(["work": spent(resets: resetsAt)], eligible: ["work"],
                             blindness: blind(landed: false))
        XCTAssertEqual(decision(in: notAPoll), .nowhereToGo(.atALimit(.session, .noOtherHat)),
                       "the decision is the same one")
        XCTAssertNil(warning(in: notAPoll),
                     "opening the popover or touching the toggle asks the same question of the "
                         + "same numbers; answering it with a notification would fire on a window "
                         + "the person opened themselves")
    }

    func testTheSwitchBeingOffIsSilenceAndNotADeadEnd() {
        var off = armed
        off.isOn = false
        let stranded = theDayItWentQuiet(resets: resetsAt)
        XCTAssertEqual(decision(in: stranded, policy: off), .hold,
                       "decide refuses under guard isOn before any limit is looked at")
        XCTAssertNil(warning(in: stranded, policy: off),
                     "nothing is going to move, so there is nothing to tell anybody about")
    }

    private func change(
        _ incoming: AutoSwitchWarning?,
        held: AutoSwitchWarning? = nil,
        announced: AutoSwitchWarning? = nil,
        notifies: Bool = true
    ) -> AutoSwitchWarningChange {
        AutoSwitchWarningChange.of(incoming, held: held, announced: announced, notifies: notifies)
    }

    private var stuck: AutoSwitchWarning {
        .nowhereToGoAtALimit(.session, .othersAreSpent(freesUpAt: resetsAt))
    }

    func testEveryPollKeepsWhatItSawSoTheDotHasSomethingToBeDrawnFrom() {
        XCTAssertEqual(change(stuck).keeps, stuck,
                       "this is the value the menu bar is drawn from, the one VoiceOver reads and "
                           + "the one the popover banner is built from: dropping it leaves the dot "
                           + "dark for this warning and for the three the parent branch added, "
                           + "while the notification, keyed off an episode that never advances, "
                           + "goes out every 300 seconds")
        XCTAssertNil(change(nil, held: stuck).keeps,
                     "and a dead end that ended is kept as the absence it is")
        XCTAssertTrue(change(stuck).redraws)
        XCTAssertTrue(change(nil, held: stuck).redraws, "the dot has to go out as well as come on")
        XCTAssertFalse(change(stuck, held: stuck, announced: stuck).redraws,
                       "an unchanged poll redraws nothing; a redraw every 300 seconds is work "
                           + "nobody asked for")
        XCTAssertTrue(change(stuck).announces)
        XCTAssertFalse(change(stuck, held: stuck, announced: stuck).announces,
                       "once an episode, which is the rule the spec names")
        XCTAssertFalse(change(nil, held: stuck, announced: stuck).announces,
                       "an ending is a dot going out, not something to say")
    }

    func testAnHourArrivingOnALaterPollIsKeptWithoutReopeningTheNotification() {
        let withoutTheHour = AutoSwitchWarning.nowhereToGoAtALimit(.session,
                                                                   .othersAreSpent(freesUpAt: nil))
        let later = change(stuck, held: withoutTheHour, announced: withoutTheHour)
        XCTAssertFalse(later.announces,
                       "the person has already been told about this dead end, and telling them "
                           + "again is the five-minute repeat the whole episode rule exists against")
        XCTAssertEqual(later.keeps, stuck,
                       "but the hour is kept, and the popover banner is built from the kept value, "
                           + "so an hour that arrives after the notification still reaches them")
        XCTAssertTrue(later.redraws)
    }

    func testADeadEndThatChangesItsSentenceIsANewFactAndIsSaidAgain() {
        let needsSigningIn = AutoSwitchWarning.nowhereToGoAtALimit(
            .session, .othersNeedSigningIn(shutOut("personal"), alsoShutOut: [])
        )
        XCTAssertTrue(change(needsSigningIn, held: stuck, announced: stuck).announces,
                      "\"wait for a window\" and \"sign this hat in\" ask different things of the "
                          + "person")
        XCTAssertTrue(change(.nowhereToGoAtALimit(.weekly, .othersAreSpent(freesUpAt: resetsAt)),
                             held: stuck, announced: stuck).announces,
                      "a second window closing after the first is a new fact too")
        XCTAssertFalse(change(stuck,
                              held: stuck,
                              announced: .nowhereToGoAtALimit(.session,
                                                              .othersAreSpent(freesUpAt: sooner))).announces,
                       "but only the hour moving is not: the reason is the same")

        let twoShutOut = AutoSwitchWarning.nowhereToGoAtALimit(
            .session, .othersNeedSigningIn(shutOut("personal"), alsoShutOut: [shutOut("team")])
        )
        let threeShutOut = AutoSwitchWarning.nowhereToGoAtALimit(
            .session,
            .othersNeedSigningIn(shutOut("personal"), alsoShutOut: [shutOut("team"), shutOut("spare")])
        )
        XCTAssertFalse(change(threeShutOut, held: twoShutOut, announced: twoShutOut).announces,
                       "two shut-out hats and three produce the same sentence word for word, so a "
                           + "third one appearing must not wake the person with a notification "
                           + "they have already read. The episode is what the person sees, not "
                           + "what the value holds")
        XCTAssertTrue(change(twoShutOut, held: needsSigningIn, announced: needsSigningIn).announces,
                      "one to two does change the sentence - the name drops out of it - so that "
                          + "repeat is earned")
    }

    func testADeadEndThatEndsRearmsTheWarning() {
        let raised = warning(in: theDayItWentQuiet(resets: resetsAt))
        XCTAssertNotNil(raised)
        XCTAssertNil(warning(in: theDayItWentQuiet(resets: resetsAt, room: 5)),
                     "a hat with room turned up, so there is nothing left to warn about and the "
                         + "dot goes out")
        XCTAssertFalse(AutoSwitchWarning.isTheSameEpisode(raised, as: nil),
                       "which rearms it: the next time the person is stranded they are told again")
        XCTAssertFalse(AutoSwitchWarning.isTheSameEpisode(nil, as: raised))
    }

    func testAnEpisodeThatEndedIsForgottenSoTheNextOneIsSaidOutLoud() {
        XCTAssertNil(change(nil, held: stuck, announced: stuck).remembers,
                     "the end of an episode has to clear what was said, or the next dead end of "
                         + "the same kind is taken for the one already announced and the person "
                         + "hears nothing at all. The parent branch got this for free by writing "
                         + "one field before the notification guard; splitting the two put the "
                         + "clearing on a path that announces == false never reaches, and it hit "
                         + "all four warnings, not only the new one")
        XCTAssertEqual(change(stuck).remembers, stuck, "and saying it is what records it")
        XCTAssertEqual(change(stuck, held: stuck, announced: stuck).remembers, stuck,
                       "a repeat of the same episode neither says nor forgets")
        XCTAssertNil(change(stuck, notifies: false).remembers,
                     "with notifications off nothing was said, so nothing is recorded as said - "
                         + "which is what lets turning them on mid-episode still tell the person")
        XCTAssertFalse(change(stuck, notifies: false).announces)
        XCTAssertEqual(change(stuck, notifies: false).keeps, stuck,
                       "the dot is raised either way; only the notification is withheld")
    }

    func testAnEpisodeNobodyWasToldAboutIsStillWaitingToBeTold() {
        XCTAssertTrue(change(stuck, held: stuck, announced: nil).announces,
                      "with notifications off the poll keeps the warning and says nothing, so the "
                          + "announced memory stays empty - turning them on mid-episode then tells "
                          + "the person on the next landed poll instead of never")
        XCTAssertFalse(change(stuck, held: stuck, announced: stuck).announces,
                       "and once it has actually been said, it is not said again")
    }

    func testAWarningReplacedByADifferentOneIsNotSwallowed() {
        XCTAssertFalse(AutoSwitchWarning.isTheSameEpisode(.willSwitchWhenItCan, as: .nowhereFreshToGo),
                       "two warnings that are both present and different are different episodes - "
                           + "the fallback branch compares the values, and comparing only whether "
                           + "each side is present would call every pair of them the same")
        XCTAssertTrue(change(.nowhereToGoAtALimit(.session, .noOtherHat),
                             held: .willSwitchWhenItCan,
                             announced: .willSwitchWhenItCan).announces,
                      "the usage stopped being readable and the person was told; the network came "
                          + "back, the limit was measured and there is nowhere to go. Swallowing "
                          + "that leaves them on \"Can't read usage\" while the real answer is a "
                          + "dead end at a limit")
        XCTAssertTrue(AutoSwitchWarning.isTheSameEpisode(.everyOtherHatIsSpent, as: .everyOtherHatIsSpent))
    }

    private func strandedSnapshot(
        _ warning: AutoSwitchWarning?,
        isOn: Bool = true,
        alsoHolding others: [String] = []
    ) -> HatsSnapshot {
        func hat(_ id: String, _ name: String) -> Account {
            var hat = Account(id: id, email: "\(id)@x.co", browser: nil)
            hat.name = name
            hat.hasStoredCredentials = true
            hat.identity = CLIIdentity(oauthAccount: [:], userID: nil)
            return hat
        }
        var snapshot = HatsSnapshot()
        snapshot.settings.autoSwitch.isOn = isOn
        snapshot.rows = [HatRowState(hat: hat("work", "Work"), isWearing: true,
                                     usage: nil, usageTrouble: nil)]
            + others.map {
                HatRowState(hat: hat($0, $0.capitalized), isWearing: false,
                            usage: nil, usageTrouble: nil)
            }
        snapshot.autoSwitchWarning = warning
        return snapshot
    }

    func testThePopoverCarriesTheDeadEndForAsLongAsItLasts() {
        let stranded = strandedSnapshot(stuck)
        XCTAssertEqual(stranded.deadEndBanner(now: now, timeZone: utc)?.line,
                       "Work reached its 5-hour limit, and no other hat has room. Something frees "
                           + "up at 09:00, or sooner if you reset a limit.",
                       "one notification is easy to miss and the dead end held for an hour on "
                           + "2026-09-25; the banner is read off the kept warning, so it lasts "
                           + "exactly as long as the dead end rather than until somebody looks")
        XCTAssertNil(stranded.deadEndBanner(now: now, timeZone: utc)?.signInTo,
                     "waiting for a window is not something a button can do")
        XCTAssertNil(strandedSnapshot(.willSwitchWhenItCan).deadEndBanner(now: now, timeZone: utc),
                     "a usage that cannot be read has the dot and its own notification, and the "
                         + "banner is not a second home for every warning")
        XCTAssertNil(strandedSnapshot(nil).deadEndBanner(now: now, timeZone: utc))
        XCTAssertNil(strandedSnapshot(.nowhereToGoAtALimit(.session, .noOtherHat), isOn: false)
            .deadEndBanner(now: now, timeZone: utc),
            "with auto-switching off nothing is going to move, so there is nothing to announce")
    }

    func testTheBannerOffersTheLoginItNamesAndOnlyWhenItNamesOne() {
        let one = AutoSwitchWarning.nowhereToGoAtALimit(
            .session, .othersNeedSigningIn(shutOut("personal"), alsoShutOut: [])
        )
        XCTAssertEqual(strandedSnapshot(one, alsoHolding: ["personal"])
            .deadEndBanner(now: now, timeZone: utc)?.signInTo,
            shutOut("personal"),
            "the sentence names an action, and the banner beside it carries the button for that "
                + "action - the switch-back banner in the same view has done this all along, and "
                + "relogin was already on HatsActions")
        let two = AutoSwitchWarning.nowhereToGoAtALimit(
            .session, .othersNeedSigningIn(shutOut("personal"), alsoShutOut: [shutOut("team")])
        )
        XCTAssertNil(strandedSnapshot(two, alsoHolding: ["personal", "team"])
            .deadEndBanner(now: now, timeZone: utc)?.signInTo,
            "with two of them a single button would have to pick one, and the sentence "
                + "deliberately names neither")
    }

    func testAHatRemovedUnderneathTakesItsSentenceWithIt() {
        let names = AutoSwitchWarning.nowhereToGoAtALimit(
            .session, .othersNeedSigningIn(shutOut("personal"), alsoShutOut: [])
        )
        XCTAssertNotNil(strandedSnapshot(names, alsoHolding: ["personal"])
            .deadEndBanner(now: now, timeZone: utc))
        let gone = strandedSnapshot(names)
        XCTAssertNil(gone.deadEndBanner(now: now, timeZone: utc),
                     "a hat can be removed between the poll that named it and the next redraw, and "
                         + "a banner naming a hat the person just deleted is worse than no banner "
                         + "for the second it takes the poll to land")
        XCTAssertEqual(gone.menuBarAccessibilityLabel, "Hats — wearing Work",
                       "the spoken label is read off the same guard, so it does not announce it "
                           + "either")
        XCTAssertFalse(gone.showsAWarningAboutTheWornHat,
                       "and the dot goes with them: one guard, all three consumers")
    }

    func testTheJournalCarriesWhichDeadEndItWas() {
        XCTAssertEqual(AutoSwitchDeadEnd.StrandedBy.noOtherHat.journalReason, "noOtherHat",
                       "the journal is what a person greps at 10:45 after an hour of identical "
                           + "lines, and the most diagnostic half of the answer used to be "
                           + "computed and dropped on the floor")
        XCTAssertEqual(AutoSwitchDeadEnd.StrandedBy.othersAreSpent(freesUpAt: nil).journalReason,
                       "othersAreSpent")
        XCTAssertEqual(AutoSwitchDeadEnd.noFreshReading.journalLimit, "usageCouldNotBeRead",
                       "the blind dead end keeps the word it has always written")
        XCTAssertEqual(AutoSwitchDeadEnd.noFreshReading.journalReason, "-")
    }

    func testTheJournalReopensOnAChangeOfReasonAndNotOnlyOfLimit() {
        let spentAtSession = NowhereToGoLine.of(.atALimit(.session, .othersAreSpent(freesUpAt: resetsAt)))
        let signInAtSession = NowhereToGoLine.of(
            .atALimit(.session, .othersNeedSigningIn(shutOut("personal"), alsoShutOut: []))
        )
        XCTAssertNotEqual(spentAtSession.key, signInAtSession.key,
                          "the same limit stranded the person for two different reasons, and the "
                              + "line is written through NoteOnChange - keying it on the limit "
                              + "alone means the second reason never reaches the journal at all")
        XCTAssertEqual(spentAtSession.key,
                       NowhereToGoLine.of(.atALimit(.session, .othersAreSpent(freesUpAt: nil))).key,
                       "the hour moving is not a new fact and must not reopen an hour of lines")
        XCTAssertEqual(spentAtSession.limit, "session")
        XCTAssertEqual(spentAtSession.reason, "othersAreSpent")
    }

    func testTheShutOutListIsReadOffTheSameRowsTheEligibleListIs() {
        func hat(_ id: String, _ name: String, switchable: Bool) -> Account {
            var hat = Account(id: id, email: "\(id)@x.co", browser: nil)
            hat.name = name
            hat.hasStoredCredentials = switchable
            if switchable { hat.identity = CLIIdentity(oauthAccount: [:], userID: nil) }
            return hat
        }
        let rows = [
            HatRowState(hat: hat("work", "Work", switchable: true), isWearing: true,
                        usage: nil, usageTrouble: nil),
            HatRowState(hat: hat("personal", "Personal", switchable: false), isWearing: false,
                        usage: nil, usageTrouble: nil),
        ]
        XCTAssertEqual(AutoSwitchEngine.eligible(in: rows), ["work"])
        XCTAssertEqual(AutoSwitchEngine.blocked(in: rows).map(\.id), ["personal"],
                       "the two lists are complements read off one pass of the same rows, so a hat "
                           + "can never be in both or in neither")
        XCTAssertEqual(AutoSwitchEngine.blocked(in: rows).first?.title, "Personal",
                       "the title travels with it, because the sentence names the hat")
        XCTAssertEqual(AutoSwitchEngine.blocked(in: rows).first?.blocker, "needs login",
                       "and so does the blocker's own wording, which is the whole point of not "
                           + "writing one phrase for five different blockers")
        XCTAssertEqual(AutoSwitchEngine.blocked(in: rows).first?.loginAction, "Log in…",
                       "and the button's wording: personal has no stored credential, so there is "
                           + "no login to repeat and no \"again\" to speak of")

        var halfWayIn = hat("spare", "Spare", switchable: false)
        halfWayIn.hasStoredCredentials = true
        let secondLogin = AutoSwitchEngine.blocked(in: [
            HatRowState(hat: halfWayIn, isWearing: false, usage: nil, usageTrouble: nil),
        ])
        XCTAssertEqual(secondLogin.first?.blocker, "needs one more login")
        XCTAssertEqual(secondLogin.first?.loginAction, "Log in again…",
                       "a hat with a stored credential and no identity yet HAS been logged into "
                           + "once, so its button says again - which is the distinction the "
                           + "project already draws in HatRowState and the reason the banner reads "
                           + "it rather than writing one label for every blocked hat")
    }

    private func sourceOf(_ name: String) -> String {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/\(name)")

        return (try? String(contentsOf: source, encoding: .utf8)) ?? ""
    }

    func testTheDecisionOfNoteTheWarningIsWiredToTheFieldsAndNotOnlyComputed() throws {
        let text = sourceOf("AppDelegate+AutoSwitch.swift")
        let computed = try XCTUnwrap(text.range(of: "AutoSwitchWarningChange.of(")).lowerBound
        let stored = try XCTUnwrap(text.range(of: "lastAutoSwitchWarning = change.keeps")).lowerBound
        let called = try XCTUnwrap(text.range(of: "noteTheWarning(warning, on: snapshot, at: now)")).lowerBound
        let deadEnd = try XCTUnwrap(text.range(of: "if case .nowhereToGo(let deadEnd)")).lowerBound

        XCTAssertLessThan(computed, stored,
                          "the answer is computed and then held - holding it is what the dot, the "
                              + "spoken label, the banner and the episode all read, and dropping "
                              + "that one line leaves every warning in this app invisible while "
                              + "the notification repeats every 300 seconds")
        XCTAssertLessThan(called, deadEnd,
                          "and noteTheWarning is called above the dead-end branch, which returns "
                              + "out of decideAutoSwitch after writing its journal line")
        XCTAssertTrue(text.contains("if change.redraws { redraw() }"),
                      "the redraw is asked for, not merely decided: removing this call leaves the "
                          + "menu bar drawn from whatever the last unrelated redraw put there, and "
                          + "it survived every behaviour test in this file")
        XCTAssertTrue(text.contains("lastAnnouncedWarning = change.remembers"),
                      "and what was said is held from the same answer, unconditionally - the "
                          + "version that wrote it only inside the notification branch could never "
                          + "record an ending")
        XCTAssertTrue(text.contains("lastAutoSwitchNowhere.shouldWrite(line.key)"),
                      "the journal line is deduplicated on the whole answer, not on the limit alone")
        XCTAssertTrue(text.contains("if switchedOn { usage.poll(hatsForUsage()) }"),
                      "turning the switch on asks for a reading rather than raising the dot "
                          + "itself: a warning is an event of a poll landing")
        let forgetting = String(text[try XCTUnwrap(text.range(of: "func forgetWhatTheSwitchHasSeen")).lowerBound...])
        XCTAssertTrue(forgetting.contains("lastAutoSwitchWarning = nil"),
                      "and turning it on drops what the last poll saw rather than showing it as "
                          + "current - the poll asked for on the line above is what confirms it, "
                          + "and if no poll lands there is nothing to show")

        let actions = sourceOf("AppDelegate+Actions.swift")
        let removing = String(actions[try XCTUnwrap(actions.range(of: "func remove(")).lowerBound...])
        XCTAssertTrue(removing.contains("self.usage.poll(self.hatsForUsage())"),
                      "removing a hat changes who is left to switch to, and the reason a dead end "
                          + "gives is built from exactly that list. relogin needs no such line: a "
                          + "settled sign-in already polls from main.swift, which is the moment "
                          + "the credential actually lands")
        XCTAssertTrue(actions.contains("if self.lastAutoSwitchWarning == nil {"),
                      "and a failed wear puts back what it took only if nothing arrived meanwhile, "
                          + "so a poll that landed during those milliseconds is not overwritten by "
                          + "a value from before the attempt")

        XCTAssertTrue(sourceOf("AppDelegate+Redraw.swift")
            .contains("HatsSnapshot(autoSwitchWarning: lastAutoSwitchWarning)"),
            "the second link of the same chain: the held value reaches the snapshot here")
        XCTAssertTrue(sourceOf("HatListView.swift").contains("snapshot.deadEndBanner(now: Date())"),
                      "and the third: the banner is drawn here. Every one of these lines is a "
                          + "single edit away from switching the feature off in silence, and none "
                          + "of them is reachable by a test in this project")

        XCTAssertTrue(text.contains("if world.blindness.landedAPoll"),
                      "This test is a statement about the TEXT of these files and nothing more. It "
                          + "holds that those lines exist and stand in that order, because no test "
                          + "in this project builds AppDelegate. It does NOT hold that the popover "
                          + "or the toggle show anything: both reach noteTheWarning only through "
                          + "the landedAPoll gate asserted here, and what they show is answered by "
                          + "testOnlyALandedPollRaisesIt instead")
    }
}
