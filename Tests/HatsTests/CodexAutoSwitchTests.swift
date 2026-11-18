import XCTest
@testable import Hats

final class CodexAutoSwitchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let policy = AutoSwitchPolicy(isOn: true)

    private func hat(_ id: String, vacation: Bool = false, signedIn: Bool = true) -> Account {
        var hat = Account(id: id, email: "\(id)@example.com")
        hat.tool = .codex
        hat.hasStoredCredentials = true
        hat.codexOwner = signedIn ? CodexOwner(userID: "user-\(id)", accountID: "acct-\(id)") : nil
        if vacation { hat.vacationSince = now }
        return hat
    }

    private func window(_ minutes: Int, _ percent: Int, resets: Date? = nil) -> CodexUsageWindow {
        CodexUsageWindow(minutes: minutes, percent: percent, resetsAt: resets ?? now.addingTimeInterval(3600))
    }

    private func rows(
        worn: String = "plus",
        _ hats: [Account],
        _ windows: [String: [CodexUsageWindow]]
    ) -> [HatRowState] {
        var book = CodexUsageBook()
        for (id, seen) in windows {
            let reading = CodexUsageReading(windows: seen, plan: id)
            book.note(CodexUsageSighting(reading: reading, at: now, source: .wham), for: id)
        }
        return ClaudeDoors.codexRows(hats, worn: worn, usage: book, now: now)
    }

    private func outcome(_ rows: [HatRowState], policy: AutoSwitchPolicy? = nil) -> AutoSwitchOutcome {
        CodexAutoSwitch.outcome(policy: policy ?? self.policy, rows: rows, at: now)
    }

    func testThe5HourThresholdPutsOnTheHatWithRoomAndNamesTheSessionLimit() {
        let shown = rows([hat("plus"), hat("business")],
                         ["plus": [window(300, 91), window(10080, 10)], "business": [window(10080, 20)]])

        let switched = outcome(shown)

        XCTAssertEqual(switched.wearsHat, "business")
        XCTAssertEqual(switched.record?.from, "plus")
        XCTAssertEqual(switched.record?.limit, .session)
        XCTAssertEqual(switched.record?.journalReason, "session")
    }

    func testTheWeeklyThresholdPutsOnTheHatWithRoomAndNamesTheWeeklyLimit() {
        let shown = rows(worn: "business", [hat("plus"), hat("business")],
                         ["business": [window(10080, 96)], "plus": [window(300, 10), window(10080, 30)]])

        let switched = outcome(shown)

        XCTAssertEqual(switched.wearsHat, "plus")
        XCTAssertEqual(switched.record?.journalReason, "weekly")
    }

    func testABusinessHatWithNoFiveHourWindowIsNotTouchedByThe5HourThreshold() {
        var low = policy
        low.sessionThresholdPercent = 50
        let shown = rows(worn: "business", [hat("plus"), hat("business")],
                         ["business": [window(10080, 60)], "plus": [window(300, 10), window(10080, 30)]])

        XCTAssertEqual(outcome(shown, policy: low).decision, .hold)
        XCTAssertEqual(CodexAutoSwitch.reasonForHolding(policy: low, rows: shown, at: now), .underTheThresholds)
    }

    func testUnderTheThresholdsItHoldsAndSaysWhy() {
        let shown = rows([hat("plus"), hat("business")],
                         ["plus": [window(300, 50), window(10080, 10)], "business": [window(10080, 20)]])

        XCTAssertEqual(outcome(shown).decision, .hold)
        XCTAssertEqual(CodexAutoSwitch.reasonForHolding(policy: policy, rows: shown, at: now), .underTheThresholds)
    }

    func testWhenTheOtherHatIsSpentThereIsNowhereToGo() throws {
        let shown = rows([hat("plus"), hat("business")],
                         ["plus": [window(300, 91), window(10080, 10)], "business": [window(10080, 97)]])

        guard case .nowhereToGo(let deadEnd) = outcome(shown).decision else { return XCTFail("expected a dead end") }
        XCTAssertEqual(NowhereToGoLine.of(deadEnd), NowhereToGoLine(limit: "session", reason: "othersAreSpent"))
    }

    func testAHatOnVacationIsNotChosen() throws {
        let shown = rows([hat("plus"), hat("business", vacation: true)],
                         ["plus": [window(300, 91), window(10080, 10)], "business": [window(10080, 20)]])

        guard case .nowhereToGo(let deadEnd) = outcome(shown).decision else { return XCTFail("expected a dead end") }
        XCTAssertEqual(NowhereToGoLine.of(deadEnd).reason, "othersAreOnVacation")
    }

    func testAHatThatNeedsASignInIsNotChosen() {
        let shown = rows([hat("plus"), hat("business", signedIn: false)],
                         ["plus": [window(300, 91), window(10080, 10)], "business": [window(10080, 20)]])

        XCTAssertNil(outcome(shown).wearsHat)
        guard case .nowhereToGo(let deadEnd) = outcome(shown).decision else { return XCTFail("expected a dead end") }
        XCTAssertEqual(NowhereToGoLine.of(deadEnd).reason, "othersNeedSigningIn")
    }

    func testAWindowWhoseResetHasPassedHasNotReachedItsThreshold() {
        let shown = rows([hat("plus"), hat("business")],
                         ["plus": [window(300, 95, resets: now.addingTimeInterval(-60)), window(10080, 10)],
                          "business": [window(10080, 20)]])

        XCTAssertEqual(outcome(shown).decision, .hold)
        XCTAssertEqual(CodexAutoSwitch.readings(of: shown, at: now)["plus"]?.session?.percent, 0)
    }

    func testASpareWhoseResetHasPassedHasRoomAgain() {
        let shown = rows([hat("plus"), hat("business")],
                         ["plus": [window(300, 91), window(10080, 10)],
                          "business": [window(10080, 99, resets: now.addingTimeInterval(-60))]])

        XCTAssertEqual(outcome(shown).wearsHat, "business")
    }

    func testWithTheSwitchOffNothingHappens() {
        let shown = rows([hat("plus"), hat("business")],
                         ["plus": [window(300, 91), window(10080, 10)], "business": [window(10080, 20)]])

        XCTAssertEqual(outcome(shown, policy: AutoSwitchPolicy()).decision, .hold)
        XCTAssertEqual(CodexAutoSwitch.reasonForHolding(policy: AutoSwitchPolicy(), rows: shown, at: now), .off)
    }

    func testWithoutAReadingOfTheWornHatThereIsNoBlindSwitch() {
        let shown = rows([hat("plus"), hat("business")], ["business": [window(10080, 20)]])

        XCTAssertEqual(outcome(shown).decision, .hold)
        XCTAssertEqual(CodexAutoSwitch.reasonForHolding(policy: policy, rows: shown, at: now), .noReading)
        XCTAssertEqual(CodexAutoSwitch.world(of: shown, at: now).blindness, UsageBlindness())
    }

    func testTheOrderOfTheCodexPolicyDecidesTheSpare() {
        var ordered = policy
        ordered.order = ["team", "business"]
        let shown = rows([hat("plus"), hat("business"), hat("team")],
                         ["plus": [window(300, 91), window(10080, 10)],
                          "business": [window(10080, 20)], "team": [window(10080, 20)]])

        XCTAssertEqual(outcome(shown, policy: ordered).wearsHat, "team")
    }

    func testTheNoticeNamesTheHatAndTheLimit() throws {
        let shown = rows([hat("plus"), hat("business")],
                         ["plus": [window(300, 91), window(10080, 10)], "business": [window(10080, 20)]])

        let notice = try XCTUnwrap(AutoSwitchEngine.notice(for: outcome(shown)) { "Hat \($0)" })

        XCTAssertEqual(notice.0, "Switched to Hat business")
        XCTAssertEqual(notice.1, "Hat plus reached its 5-hour limit.")
    }

    func testTheClaudeSwitchSeesNoCodexHatAndTheCodexSwitchNoClaudeHat() {
        var snapshot = HatsSnapshot()
        var claude = Account(id: "claude", email: "claude@example.com")
        claude.hasStoredCredentials = true
        snapshot.rows = [HatRowState(hat: claude, isWearing: true, usage: nil, usageTrouble: nil)]
        snapshot.codexRows = rows([hat("plus"), hat("business")],
                                  ["plus": [window(300, 91), window(10080, 10)], "business": [window(10080, 20)]])

        let claudeWorld = AutoSwitchWorld.of(snapshot: snapshot, readings: [:], missed: MissedPolls(),
                                             fresh: [], from: .aPollLanded)
        let codexWorld = CodexAutoSwitch.world(of: snapshot.codexRows, at: now)

        XCTAssertEqual(claudeWorld.wearing, "claude")
        XCTAssertFalse(claudeWorld.eligible.contains("business"))
        XCTAssertEqual(codexWorld.wearing, "plus")
        XCTAssertFalse(codexWorld.eligible.contains("claude"))
        XCTAssertNil(codexWorld.readings["claude"])
    }

    func testAHatAtItsThresholdWithNowhereToGoGivesTheClaudeWarning() {
        let stuck = rows([hat("plus"), hat("business")],
                         ["plus": [window(300, 91), window(10080, 10)], "business": [window(10080, 97)]])
        let warning = CodexAutoSwitch.warning(for: outcome(stuck), rows: stuck)

        guard case .nowhereToGoAtALimit(.session, .othersAreSpent)? = warning else {
            return XCTFail("expected a dead end at the 5-hour limit, got \(String(describing: warning))")
        }
        let fine = rows([hat("plus"), hat("business")],
                        ["plus": [window(300, 50), window(10080, 10)], "business": [window(10080, 97)]])
        XCTAssertNil(CodexAutoSwitch.warning(for: outcome(fine), rows: fine))
        let free = rows([hat("plus"), hat("business")],
                        ["plus": [window(300, 91), window(10080, 10)], "business": [window(10080, 20)]])
        XCTAssertNil(CodexAutoSwitch.warning(for: outcome(free), rows: free), "it switches instead")
    }

    func testTheCodexDeadEndBannerNamesTheCodexHatOnTheCodexTabOnly() throws {
        var snapshot = HatsSnapshot()
        var claude = Account(id: "claude", email: "claude@example.com")
        claude.hasStoredCredentials = true
        snapshot.rows = [HatRowState(hat: claude, isWearing: true, usage: nil, usageTrouble: nil)]
        snapshot.codexRows = rows([hat("plus"), hat("business")],
                                  ["plus": [window(300, 91), window(10080, 10)], "business": [window(10080, 97)]])
        snapshot.codexAutoSwitchWarning = CodexAutoSwitch.warning(for: outcome(snapshot.codexRows),
                                                                  rows: snapshot.codexRows)
        XCTAssertNil(snapshot.deadEndBanner(on: .codex, now: now), "the Codex switch is off")

        snapshot.settings.codexAutoSwitch.isOn = true
        snapshot.settings.autoSwitch.isOn = true
        let line = try XCTUnwrap(snapshot.deadEndBanner(on: .codex, now: now)?.line)
        XCTAssertTrue(line.contains("plus@example.com"), line)
        XCTAssertNil(snapshot.deadEndBanner(on: .claudeCode, now: now), "no Claude warning was given")
        XCTAssertNil(snapshot.warningAboutTheWornHat, "the menu bar mark stays Claude's")

        snapshot.autoSwitchWarning = snapshot.codexAutoSwitchWarning
        snapshot.codexAutoSwitchWarning = nil
        XCTAssertNil(snapshot.deadEndBanner(on: .codex, now: now), "the Claude warning stays on its tab")
        XCTAssertTrue(try XCTUnwrap(snapshot.deadEndBanner(on: .claudeCode, now: now)?.line)
            .contains("claude@example.com"))
    }
}
