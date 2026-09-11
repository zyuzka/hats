import XCTest
@testable import Hats

final class PollStepTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func step(_ raw: Data, isWearing: Bool) -> AutoSwitchWatch.PollStep {
        AutoSwitchWatch.step(for: CredentialPayload(raw: raw), isWearing: isWearing, at: now)
    }

    func testAUsableTokenIsSpentOnTheUsageEndpointWhicheverHatItIs() {
        let live = credential(expiresAt: milliseconds(now.addingTimeInterval(60)))
        XCTAssertEqual(step(live, isWearing: true), .fetch("a-1"))
        XCTAssertEqual(step(live, isWearing: false), .fetch("a-1"))
        XCTAssertEqual(step(credential(expiresAt: nil), isWearing: false), .fetch("a-1"),
                       "a credential with no expiry is the shape the CLI writes before it knows one")
    }

    func testTheWornHatIsLeftToTheCLIAndIsNeverRenewedHere() {
        let expired = credential(expiresAt: milliseconds(now.addingTimeInterval(-60)))
        XCTAssertEqual(step(expired, isWearing: true), .trouble(.tokenExpired),
                       "the live slot is refreshed by the CLI under an inter-process lock, and a "
                           + "second writer there is how an operator gets logged out")
    }

    func testAParkedHatWithALiveRefreshTokenIsRenewedRatherThanReportedUnknown() {
        let expired = credential(expiresAt: milliseconds(now.addingTimeInterval(-60)))
        XCTAssertEqual(step(expired, isWearing: false), .renew("r-1", []),
                       "nothing else reads a parked slot, so the renewal Claude Code promises never "
                           + "arrives there and the row said unknown for as long as the hat lay parked")
    }

    func testAParkedHatWithNothingToRenewWithSaysSoInsteadOfPromisingARenewal() {
        let expired = milliseconds(now.addingTimeInterval(-60))
        XCTAssertEqual(step(credential(expiresAt: expired, refresh: nil), isWearing: false),
                       .trouble(.parkedNeedsLogin))
        XCTAssertEqual(step(credential(expiresAt: expired, refresh: ""), isWearing: false),
                       .trouble(.parkedNeedsLogin))
        XCTAssertEqual(step(credential(expiresAt: expired,
                                       refreshExpiresAt: milliseconds(now.addingTimeInterval(-1))),
                            isWearing: false),
                       .trouble(.parkedNeedsLogin),
                       "a refresh token past its own expiry cannot mint anything, so sending it "
                           + "would spend a request to be told what we already knew")
    }

    func testACredentialCarryingNoTokenAtAllKeepsItsOwnDiagnosis() {
        XCTAssertEqual(step(credential(access: "", expiresAt: nil, refresh: nil), isWearing: false),
                       .trouble(.noTokenStored))
        XCTAssertEqual(step(credential(access: "", expiresAt: nil, refresh: nil), isWearing: true),
                       .trouble(.noTokenStored))
        XCTAssertEqual(step(Data(#"{"mcpOAuth":{}}"#.utf8), isWearing: true), .trouble(.noTokenStored))
    }

    func testAParkedHatWithNoAccessTokenButALiveRefreshTokenIsStillRenewed() {
        XCTAssertEqual(step(credential(access: "", expiresAt: nil), isWearing: false), .renew("r-1", []),
                       "the access token is the disposable half; a hat that still holds a good "
                           + "refresh token does not need a person to log in again")
    }

    func testTheScopesStoredInTheSlotAreTheOnesTheRenewalAsksFor() {
        let raw = (try? JSONSerialization.data(withJSONObject: [
            "claudeAiOauth": [
                "accessToken": "a-1",
                "expiresAt": milliseconds(now.addingTimeInterval(-60)),
                "refreshToken": "r-1",
                "scopes": ["user:profile", "user:design:read"],
            ],
        ])) ?? Data()
        XCTAssertEqual(step(raw, isWearing: false), .renew("r-1", ["user:profile", "user:design:read"]))
    }

    func testTheReadFailuresTheBranchAlreadyToldApartStayToldApart() {
        let slot = Slot.parked("personal")
        let locked = FakeSlots([slot: Data()])
        locked.readFailures = [slot]
        XCTAssertEqual(AutoSwitchWatch.fetched([("personal", false)], world: locked.world(now: now))
            .troubles["personal"], .credentialUnreadable)

        let absent = FakeSlots([:])
        XCTAssertEqual(AutoSwitchWatch.fetched([("personal", false)], world: absent.world(now: now))
            .troubles["personal"], .nothingStored)
    }

    func testAPollThatCouldNotReachOpenUsageKeepsTheNumberItAlreadyHad() {
        let known = UsageReading(session: UsageWindow(used: 41, limit: 100, resetsAt: Date()),
                                 weekly: UsageWindow(used: 12, limit: 100, resetsAt: Date()))

        for transient: UsageTrouble in [.fetchFailed("unreachable"), .renewalFailed("http 500")] {
            let kept = AutoSwitchWatch.readingsAfterAPoll(
                ["work": known],
                keeping: ["work"],
                batch: .init(troubles: ["work": transient])
            )

            XCTAssertEqual(kept["work"], known,
                           "MeterReading.of renders a number, its age AND the latest trouble "
                               + "together, which is the case MeterReadingTests asserts — and "
                               + "dropping the number on any trouble at all meant no poll could "
                               + "ever produce it. \(transient) says nothing about the account's usage")
        }
    }

    func testAnUnknownLiveSlotDropsTheNumberRatherThanKeepingSomebodyElses() {
        let known = UsageReading(session: UsageWindow(used: 41, limit: 100, resetsAt: Date()),
                                 weekly: UsageWindow(used: 12, limit: 100, resetsAt: Date()))
        let kept = AutoSwitchWatch.readingsAfterAPoll(
            ["work": known],
            keeping: ["work"],
            batch: .init(troubles: ["work": .liveSlotUnknown])
        )

        XCTAssertNil(kept["work"],
                     "this used to be spelled .fetchFailed(\"which account file the CLI reads "
                         + "cannot be told\"), a local configuration failure wearing the label of a "
                         + "request failure. That was only untidy until the previous fix made "
                         + ".fetchFailed the case that KEEPS an earlier number — at which point the "
                         + "worn hat showed a figure while the app could not say which credential it "
                         + "belonged to")
        XCTAssertFalse(UsageTrouble.liveSlotUnknown.keepsAnEarlierReading)
    }

    func testBuildingTheWorldResolvesNothingUntilAPollAsks() {
        var asked = 0
        let world = UsageWorld(
            liveSlot: { asked += 1; return FakeSlots.live },
            read: { _ in nil },
            write: { _, _ in },
            renew: { _, _ in .failed("not asked") },
            usage: { _ in .unreachable },
            now: { self.now },
            log: { _, _ in }
        )

        XCTAssertEqual(asked, 0,
                       "the poll timer fires on the main queue and poll() used to build the real "
                           + "world before hopping off it, and building it resolved the live slot "
                           + "through configurationRemembered — a process-table sweep on the main "
                           + "thread behind a timer. The slot is a closure now, so a world costs "
                           + "nothing to hold")

        _ = AutoSwitchWatch.fetched([("personal", false), ("team", false)], world: world)

        XCTAssertEqual(asked, 0,
                       "a poll with no worn hat never needs the live slot, and this is the case "
                           + "that discriminates: resolving once up front for the whole batch also "
                           + "gives one call when a worn hat is present, so a batch with a worn hat "
                           + "cannot tell the two apart — the first version of this check could not, "
                           + "and the mutant survived it")

        _ = AutoSwitchWatch.fetched([("work", true)], world: world)

        XCTAssertEqual(asked, 1, "and it is resolved when a worn hat actually asks")
    }

    func testAWornHatWithNoResolvableSlotIsToldSoThroughThePollItself() {
        let slots = FakeSlots([:])

        let batch = AutoSwitchWatch.fetched([("work", true)],
                                            world: slots.world(now: now, liveSlot: nil))

        XCTAssertEqual(batch.troubles["work"], .liveSlotUnknown,
                       "driven through fetched rather than through the enum, because the defect was "
                           + "the construction site choosing the wrong case — a check on the case's "
                           + "own property passes whatever the site does, and the first version of "
                           + "this check let that mutant live")
    }

    func testAPollThatCannotReadTheCredentialDropsTheNumberItHad() {
        let known = UsageReading(session: UsageWindow(used: 41, limit: 100, resetsAt: Date()),
                                 weekly: UsageWindow(used: 12, limit: 100, resetsAt: Date()))

        for invalidating: UsageTrouble in [.credentialUnreadable, .nothingStored, .noTokenStored,
                                           .tokenExpired, .parkedNeedsLogin] {
            let kept = AutoSwitchWatch.readingsAfterAPoll(
                ["work": known],
                keeping: ["work"],
                batch: .init(troubles: ["work": invalidating])
            )

            XCTAssertNil(kept["work"],
                         "\(invalidating) is about the credential rather than the request, so the "
                             + "number stops standing for anything the app can still read")
        }
    }
}
