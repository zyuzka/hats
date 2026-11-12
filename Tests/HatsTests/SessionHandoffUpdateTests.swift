import XCTest
@testable import Hats

final class SessionHandoffUpdateTests: XCTestCase {
    private let version = FakePluginWorld.claude(["--version"])
    private let list = FakePluginWorld.claude(SessionHandoffSteps.listArguments)
    private let marketplaces = FakePluginWorld.claude(SessionHandoffSteps.marketplaceArguments)
    private let refreshHelp = FakePluginWorld.claude(SessionHandoffUpdateSteps.helps[0].arguments)
    private let updateHelp = FakePluginWorld.claude(SessionHandoffUpdateSteps.helps[1].arguments)
    private let refresh = FakePluginWorld.claude([
        "plugin",
        "marketplace",
        "update",
        "hats",
        "--json",
    ])
    private let update = FakePluginWorld.claude([
        "plugin",
        "update",
        "hats@hats",
        "--scope",
        "user",
        "--json",
    ])

    private var answers: [Bool] = []
    private var asked: [HatPrompt] = []
    private var informed: [(title: String, text: String)] = []

    private func createFlow(_ fake: FakePluginWorld, own: String) -> SessionHandoffFlow {
        SessionHandoffFlow(
            own: own,
            perform: { work in work(fake.world()) },
            onMain: { $0() },
            ask: { [unowned self] prompt in
                asked.append(prompt)
                return answers.isEmpty ? false : answers.removeFirst()
            },
            inform: { [unowned self] title, text in informed.append((title, text)) },
            show: {}
        )
    }

    private func outdatedFake() -> FakePluginWorld {
        let fake = FakePluginWorld()
        fake.answer(list, PluginCLISamples.listUserThroughGitHub010)
        fake.answer(marketplaces, PluginCLISamples.marketplacesThroughGitHub)
        fake.answer(refresh, PluginCLISamples.marketplaceUpdateDone)
        fake.answer(update, PluginCLISamples.updateDone010To020)

        return fake
    }

    private static func composed(_ sample: PluginCLISample, _ from: String, _ to: String) -> PluginCommandOutcome {
        FakePluginWorld.printed(sample.stdout.replacingOccurrences(of: from, with: to))
    }

    private func readyPlan(_ fake: FakePluginWorld, own: String) throws -> SessionHandoffUpdatePlan {
        guard case .ready(let plan, _) = SessionHandoffUpdateSteps.getPreparation(own: own, in: fake.world()) else {
            XCTFail("the plugin was expected to be offered for an update")
            throw NotReady()
        }
        fake.runs = []

        return plan
    }

    private func keys(_ runs: [PluginCommandLine]) -> [String] {
        runs.map { FakePluginWorld.key($0.executable, $0.arguments) }
    }

    func testAnOutdatedPluginShowsTheOfferInTheRow() {
        let fake = outdatedFake()
        let flow = createFlow(fake, own: "0.2.0")

        flow.refresh(then: nil)

        XCTAssertEqual(flow.row.offer, SessionHandoffOffer(installed: "0.1.0", own: "0.2.0"))
        let line = SessionHandoffCopy.getUpdateLine(flow.row)
        XCTAssertEqual(line?.text, "Update available: 0.1.0 \u{2192} 0.2.0")
        XCTAssertEqual(line?.spoken, "Update available: version 0.1.0 is installed, and this Hats comes with version 0.2.0")
        XCTAssertEqual(SessionHandoffCopy.getRowStatus(flow.row), "Installed from github.com/zyuzka/hats.",
                       "the number is not repeated under the offer")
        XCTAssertEqual(fake.changingRuns, [])
    }

    func testTheRowSaysUpdatingWhileTheUpdateRuns() {
        let row = SessionHandoffRow(
            face: .installed(version: "0.1.0", folder: nil, isEnabled: true, elsewhere: []),
            isBusy: true,
            offer: SessionHandoffOffer(installed: "0.1.0", own: "0.2.0"),
            isUpdating: true
        )

        XCTAssertEqual(SessionHandoffCopy.getUpdateLine(row)?.text, "Updating\u{2026}")
    }

    func testConsentRefreshesTheMarketplaceThenUpdatesAndReportsTheListedVersion() throws {
        let fake = outdatedFake()
        let flow = createFlow(fake, own: "0.2.0")
        flow.refresh(then: nil)
        fake.queue(list, [
            PluginCLISamples.listUserThroughGitHub010.outcome,
            PluginCLISamples.listUserThroughGitHub010.outcome,
            Self.composed(PluginCLISamples.listUserThroughGitHub010, "0.1.0", "0.2.0"),
        ])
        fake.runs = []
        answers = [true]
        var duringTheUpdate: SessionHandoffRow?
        fake.whenRunning = { [update = self.update] line in
            guard FakePluginWorld.key(line.executable, line.arguments) == update else { return }
            duringTheUpdate = flow.row
        }

        flow.update()

        XCTAssertEqual(duringTheUpdate?.isUpdating, true)
        XCTAssertEqual(duringTheUpdate?.isBusy, true)
        XCTAssertEqual(duringTheUpdate.flatMap { SessionHandoffCopy.getUpdateLine($0)?.text }, "Updating\u{2026}")
        XCTAssertEqual(fake.commands, [
            version,
            refreshHelp,
            updateHelp,
            list,
            marketplaces,
            list,
            marketplaces,
            refresh,
            update,
            list,
            marketplaces,
        ], "checks and one reading before the window; after consent a reading, the two commands, one reading")
        XCTAssertEqual(keys(fake.changingRuns), [refresh, update])
        XCTAssertFalse(fake.changingRuns.contains { $0.arguments.contains("-y") || $0.arguments.contains("--yes") })
        XCTAssertFalse(fake.changingRuns.contains { $0.arguments.contains("--accept-command") })
        XCTAssertEqual(asked.map(\.title), ["Update the session handoff plugin?"])
        XCTAssertEqual(informed.map(\.title), [SessionHandoffUpdateCopy.updatedTitle])
        XCTAssertEqual(informed.first?.text, "Updated to 0.2.0. " + SessionHandoffUpdateCopy.reloadNote)
        XCTAssertEqual(flow.row.face, .installed(version: "0.2.0", folder: nil, isEnabled: true, elsewhere: []))
        XCTAssertNil(flow.row.offer)
        XCTAssertFalse(flow.row.isBusy)
        XCTAssertFalse(flow.row.isUpdating)
    }

    func testTheConsentWindowNamesTheCommandsTheFolderTheClaudeAndBothVersions() throws {
        let plan = try readyPlan(outdatedFake(), own: "0.2.0")

        let text = SessionHandoffPrompts.createUpdate(plan).text

        for part in [
            "with the Claude Code at \(FakePluginWorld.cli)",
            "claude plugin marketplace update hats --json\nclaude plugin update hats@hats --scope user --json",
            "recorded in the settings folder \(FakePluginWorld.configFolder)",
            "from version 0.1.0 to the version GitHub offers now; this Hats comes with 0.2.0",
            "Your resume notes, your own steps, your hooks and your settings stay",
            "stays switched off",
            "/reload-plugins",
        ] {
            XCTAssertTrue(text.contains(part), "missing: \(part)\n\(text)")
        }
        XCTAssertEqual(SessionHandoffPrompts.createUpdate(plan).buttons, ["Update", "Cancel"])
    }

    func testCancelInTheUpdateWindowChangesNothing() {
        let fake = outdatedFake()
        let flow = createFlow(fake, own: "0.2.0")
        flow.refresh(then: nil)
        answers = [false]

        flow.update()

        XCTAssertEqual(asked.map(\.title), ["Update the session handoff plugin?"])
        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertTrue(informed.isEmpty)
        XCTAssertFalse(flow.row.isBusy)
        XCTAssertEqual(flow.row.offer, SessionHandoffOffer(installed: "0.1.0", own: "0.2.0"))
    }

    func testAFreshPluginOffersNothingAndUpdateAsksNothing() {
        let fake = outdatedFake()
        fake.answers[list] = Self.composed(PluginCLISamples.listUserThroughGitHub010, "0.1.0", "0.2.0")
        let flow = createFlow(fake, own: "0.2.0")
        flow.refresh(then: nil)
        answers = [true]

        flow.update()

        XCTAssertNil(flow.row.offer)
        XCTAssertNil(SessionHandoffCopy.getUpdateLine(flow.row))
        XCTAssertEqual(asked, [])
        XCTAssertEqual(fake.changingRuns, [])
    }

    func testAPluginFromAFolderIsNeverOfferedAndKeepsItsRow() {
        let fake = FakePluginWorld()
        fake.answer(list, PluginCLISamples.listUserFromFolder)
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)
        let flow = createFlow(fake, own: "9.9.9")

        flow.refresh(then: nil)

        XCTAssertNil(flow.row.offer)
        XCTAssertEqual(SessionHandoffCopy.getRowStatus(flow.row), "Installed (version 0.1.0) from the folder /market.")
    }

    func testGitHubOfferingMoreIsReportedAsTheListedVersion() throws {
        let fake = outdatedFake()
        let plan = try readyPlan(fake, own: "0.2.0")
        fake.queue(list, [
            PluginCLISamples.listUserThroughGitHub010.outcome,
            Self.composed(PluginCLISamples.listUserThroughGitHub010, "0.1.0", "0.3.0"),
        ])

        let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

        XCTAssertEqual(report.title, SessionHandoffUpdateCopy.updatedTitle)
        XCTAssertEqual(report.text, "Updated to 0.3.0. " + SessionHandoffUpdateCopy.reloadNote)
    }

    func testNothingChangedSaysClaudeCodeStillListsTheOldVersion() throws {
        let fake = outdatedFake()
        fake.answer(update, PluginCLISamples.updateUpToDate010)
        let plan = try readyPlan(fake, own: "0.2.0")

        let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

        XCTAssertEqual(report.title, SessionHandoffUpdateCopy.notUpdatedTitle)
        XCTAssertEqual(report.text, "Not updated: Claude Code still lists 0.1.0, and this Hats comes with 0.2.0. "
            + "GitHub may not offer it yet.")
        XCTAssertEqual(report.face, .installed(version: "0.1.0", folder: nil, isEnabled: true, elsewhere: []))
    }

    func testAnUpdateShortOfOwnSaysGitHubDoesNotOfferOwnYet() throws {
        let fake = outdatedFake()
        let plan = try readyPlan(fake, own: "0.3.0")
        fake.queue(list, [
            PluginCLISamples.listUserThroughGitHub010.outcome,
            Self.composed(PluginCLISamples.listUserThroughGitHub010, "0.1.0", "0.2.0"),
        ])

        let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

        XCTAssertEqual(report.title, SessionHandoffUpdateCopy.updatedTitle)
        XCTAssertEqual(report.text, "Updated to 0.2.0; this Hats comes with 0.3.0, which GitHub does not offer yet. "
            + SessionHandoffUpdateCopy.reloadNote)
    }

    func testASwitchedOffPluginIsOfferedUpdatedAndToldHowToTurnItOn() throws {
        let fake = outdatedFake()
        fake.answer(list, PluginCLISamples.listOffThroughGitHub010)
        let plan = try readyPlan(fake, own: "0.2.0")
        fake.queue(list, [
            PluginCLISamples.listOffThroughGitHub010.outcome,
            PluginCLISamples.listOffThroughGitHub020.outcome,
        ])

        let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

        XCTAssertEqual(report.title, SessionHandoffUpdateCopy.updatedTitle)
        XCTAssertEqual(report.text, "Updated to 0.2.0. " + SessionHandoffUpdateCopy.reloadNote + " "
            + SessionHandoffUpdateCopy.offNote)
        XCTAssertTrue(report.text.contains("claude plugin enable hats@hats --scope user"))
        XCTAssertEqual(report.face, .installed(version: "0.2.0", folder: nil, isEnabled: false, elsewhere: []))
    }

    func testOnlyTheUserInstallationIsUpdatedAndTheProjectOneStaysApart() throws {
        let fake = outdatedFake()
        fake.answer(list, PluginCLISamples.listUserAndProjectThroughGitHub010)
        let plan = try readyPlan(fake, own: "0.2.0")
        fake.queue(list, [
            PluginCLISamples.listUserAndProjectThroughGitHub010.outcome,
            PluginCLISamples.listUserAndProjectThroughGitHub020.outcome,
        ])

        let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

        XCTAssertEqual(keys(fake.changingRuns), [refresh, update])
        XCTAssertEqual(fake.changingRuns.last?.arguments.suffix(3), ["--scope", "user", "--json"])
        let project = PluginRecord(id: "hats@hats", scope: "project", version: "0.1.0", projectPath: "/tmp/proj", isEnabled: true)
        XCTAssertEqual(report.face, .installed(version: "0.2.0", folder: nil, isEnabled: true, elsewhere: [project]))
        XCTAssertEqual(report.title, SessionHandoffUpdateCopy.updatedTitle)
    }

    func testAFailedRefreshSkipsTheUpdateReadsTheListOnceAndSaysWhy() throws {
        let fake = outdatedFake()
        fake.answer(refresh, PluginCLISamples.marketplaceUpdateRepositoryGone)
        let plan = try readyPlan(fake, own: "0.2.0")

        let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

        XCTAssertEqual(fake.commands, [list, marketplaces, refresh, list, marketplaces])
        XCTAssertEqual(keys(fake.changingRuns), [refresh], "after a failed refresh plugin update is not run")
        XCTAssertEqual(report.title, SessionHandoffUpdateCopy.notUpdatedTitle)
        XCTAssertTrue(report.text.hasPrefix("Not updated: Claude Code still lists 0.1.0, and this Hats comes with "
            + "0.2.0. claude plugin marketplace update did not answer cleanly (Failed to refresh marketplace 'hats': "
            + "Fetching the marketplace from GitHub failed"), report.text)
        XCTAssertFalse(report.text.contains("GitHub may not offer it yet"), "a failure gives its reason instead")
    }

    func testARefreshThatTimesOutSkipsTheUpdate() throws {
        let fake = outdatedFake()
        fake.answers[refresh] = PluginCommandOutcome(end: .timedOut)
        let plan = try readyPlan(fake, own: "0.2.0")

        let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

        XCTAssertEqual(keys(fake.changingRuns), [refresh])
        XCTAssertTrue(report.text.hasSuffix("claude plugin marketplace update did not answer cleanly (timed out)."),
                      report.text)
    }

    func testAnUpdateThatFailsAndChangesNothingSaysWhy() throws {
        let fake = outdatedFake()
        fake.answers[update] = PluginCommandOutcome(end: .timedOut)
        let plan = try readyPlan(fake, own: "0.2.0")

        let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

        XCTAssertEqual(report.title, SessionHandoffUpdateCopy.notUpdatedTitle)
        XCTAssertEqual(report.text, "Not updated: Claude Code still lists 0.1.0, and this Hats comes with 0.2.0. "
            + "claude plugin update did not answer cleanly (timed out).")
        XCTAssertEqual(fake.commands.filter { $0 == update }.count, 1, "a failure is reported, not retried")
    }

    func testARefreshThatFailedInsideTheUpdateIsReportedAsItsReason() throws {
        let fake = outdatedFake()
        fake.answer(update, PluginCLISamples.updateRefreshFailed)
        let plan = try readyPlan(fake, own: "0.2.0")

        let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

        XCTAssertEqual(report.title, SessionHandoffUpdateCopy.notUpdatedTitle)
        XCTAssertTrue(report.text.contains("claude plugin update did not answer cleanly (hats is already at the latest "
            + "version (0.1.0). Warning: marketplace not refreshed"), report.text)
        XCTAssertFalse(report.text.contains("GitHub may not offer it yet"), report.text)
    }

    func testAnUpdateThatTimedOutButReachedIsASuccessWithACaveat() throws {
        let fake = outdatedFake()
        fake.answers[update] = PluginCommandOutcome(end: .timedOut)
        let plan = try readyPlan(fake, own: "0.2.0")
        fake.queue(list, [
            PluginCLISamples.listUserThroughGitHub010.outcome,
            Self.composed(PluginCLISamples.listUserThroughGitHub010, "0.1.0", "0.2.0"),
        ])

        let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

        XCTAssertEqual(report.title, SessionHandoffUpdateCopy.updatedTitle)
        XCTAssertEqual(report.text, "Updated to 0.2.0. claude plugin update did not answer cleanly (timed out), but "
            + "the plugin list shows 0.2.0. " + SessionHandoffUpdateCopy.reloadNote)
    }

    func testAnUnreadableListAfterTheUpdateClaimsNoSuccessAndIsNotRetried() throws {
        let fake = outdatedFake()
        let plan = try readyPlan(fake, own: "0.2.0")
        fake.queue(list, [
            PluginCLISamples.listUserThroughGitHub010.outcome,
            PluginCommandOutcome(end: .timedOut),
        ])

        let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

        XCTAssertEqual(report.title, SessionHandoffUpdateCopy.unconfirmedTitle)
        XCTAssertEqual(report.text, "claude plugin update answered ok. The plugin list of Claude Code could not be "
            + "read: timed out. Hats cannot tell whether the plugin was updated.")
        guard case .unknown = report.face else { return XCTFail("expected an unknown state, got \(String(describing: report.face))") }
        XCTAssertEqual(fake.commands, [list, marketplaces, refresh, update, list])
    }

    func testAListAfterTheCommandsThatIsNeitherOlderNorNewerSaysWhatItReads() throws {
        let cases: [(why: String, list: PluginCommandOutcome, face: SessionHandoffFace)] = [
            ("gone", PluginCLISamples.listEmpty.outcome, .notInstalled(elsewhere: [])),
            (
                "below the version before",
                Self.composed(PluginCLISamples.listUserThroughGitHub010, "0.1.0", "0.0.9"),
                .installed(version: "0.0.9", folder: nil, isEnabled: true, elsewhere: [])
            ),
        ]

        for (why, listed, face) in cases {
            let fake = outdatedFake()
            let plan = try readyPlan(fake, own: "0.2.0")
            fake.queue(list, [
                PluginCLISamples.listUserThroughGitHub010.outcome,
                listed,
            ])

            let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

            XCTAssertEqual(report.title, SessionHandoffUpdateCopy.notUpdatedTitle, why)
            XCTAssertTrue(report.text.contains("The plugin list now reads: "), why + ": " + report.text)
            XCTAssertEqual(report.face, face, why)
        }
    }

    func testAListThatIsNoLongerOutdatedBeforeTheWindowSettlesWithoutAsking() {
        let fake = outdatedFake()
        let flow = createFlow(fake, own: "0.2.0")
        flow.refresh(then: nil)
        fake.answers[list] = Self.composed(PluginCLISamples.listUserThroughGitHub010, "0.1.0", "0.2.0")
        answers = [true]

        flow.update()

        XCTAssertEqual(asked, [])
        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertEqual(informed.map(\.title), [SessionHandoffUpdateCopy.notUpdatedTitle])
        XCTAssertTrue(informed.first?.text.hasPrefix("Nothing to update.") == true, informed.first?.text ?? "")
        XCTAssertNil(flow.row.offer)
        XCTAssertFalse(flow.row.isBusy)
    }

    func testAListThatCannotBeReadBeforeTheWindowSaysSoWithoutNothingToUpdate() {
        let fake = outdatedFake()
        let flow = createFlow(fake, own: "0.2.0")
        flow.refresh(then: nil)
        fake.answers[list] = PluginCommandOutcome(end: .timedOut)
        answers = [true]

        flow.update()

        XCTAssertEqual(asked, [])
        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertEqual(informed.map(\.title), [SessionHandoffUpdateCopy.notUpdatedTitle])
        XCTAssertEqual(informed.first?.text, "The plugin list of Claude Code could not be read: timed out.")
        XCTAssertFalse(flow.row.isBusy)
    }

    func testAListThatChangedWhileTheWindowWasOpenChangesNothing() throws {
        let cases: [(why: String, list: PluginCommandOutcome, marketplaces: PluginCommandOutcome)] = [
            ("removed", PluginCLISamples.listEmpty.outcome, PluginCLISamples.marketplacesThroughGitHub.outcome),
            (
                "updated meanwhile",
                Self.composed(PluginCLISamples.listUserThroughGitHub010, "0.1.0", "0.2.0"),
                PluginCLISamples.marketplacesThroughGitHub.outcome
            ),
            (
                "another older version",
                Self.composed(PluginCLISamples.listUserThroughGitHub010, "0.1.0", "0.1.5"),
                PluginCLISamples.marketplacesThroughGitHub.outcome
            ),
            ("now from a folder", PluginCLISamples.listUserFromFolder.outcome, PluginCLISamples.marketplacesFolder.outcome),
            (
                "now from another repository",
                PluginCLISamples.listUserThroughGitHub010.outcome,
                Self.composed(PluginCLISamples.marketplacesThroughGitHub, "zyuzka/hats", "someone-else/hats")
            ),
            ("unreadable", PluginCommandOutcome(end: .timedOut), PluginCLISamples.marketplacesThroughGitHub.outcome),
        ]

        for (why, listed, origin) in cases {
            let fake = outdatedFake()
            let plan = try readyPlan(fake, own: "0.2.0")
            fake.answers[list] = listed
            fake.answers[marketplaces] = origin

            let report = SessionHandoffUpdateSteps.getChange(plan, in: fake.world())

            XCTAssertEqual(fake.changingRuns, [], why)
            XCTAssertEqual(report.title, SessionHandoffUpdateCopy.notUpdatedTitle, why)
            XCTAssertTrue(report.text.hasPrefix("Nothing was updated: the plugin list changed while the window was "
                + "open. "), why)
            XCTAssertEqual(report.face, SessionHandoffSteps.findReading(of: plan.target, in: fake.world()).face, why)
        }
    }

    func testTheRowShowsWhatTheListBecameWhileTheWindowWasOpen() {
        let fake = outdatedFake()
        let flow = createFlow(fake, own: "0.2.0")
        flow.refresh(then: nil)
        answers = [true]
        fake.queue(list, [
            PluginCLISamples.listUserThroughGitHub010.outcome,
            PluginCLISamples.listEmpty.outcome,
        ])

        flow.update()

        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertEqual(flow.row.face, .notInstalled(elsewhere: []))
        XCTAssertNil(flow.row.offer)
        XCTAssertEqual(informed.map(\.title), [SessionHandoffUpdateCopy.notUpdatedTitle])
    }

    func testAnOldClaudeIsRefusedNamingTheCommandThatLacksJSON() {
        let withoutJSON = FakePluginWorld.printed("Usage: claude plugin update [options] <plugin>\n\n"
            + "Options:\n  -h, --help  Display help for command\n")
        for (help, command) in [(refreshHelp, "claude plugin marketplace update"), (updateHelp, "claude plugin update")] {
            let fake = outdatedFake()
            fake.answers[help] = withoutJSON

            let preparation = SessionHandoffUpdateSteps.getPreparation(own: "0.2.0", in: fake.world())

            let refusal = SessionHandoffRefusal.cliTooOld(path: FakePluginWorld.cli, command: command, option: "--json")
            XCTAssertEqual(preparation, .refused(refusal), command)
            XCTAssertTrue(SessionHandoffCopy.getText(refusal).contains("its \(command) has no --json option"), command)
            XCTAssertEqual(fake.changingRuns, [], command)
        }
    }

    func testAHelpThatDoesNotAnswerIsRefusedApartFromAnOldClaude() {
        let fake = outdatedFake()
        fake.answers[updateHelp] = PluginCommandOutcome(end: .timedOut)

        let preparation = SessionHandoffUpdateSteps.getPreparation(own: "0.2.0", in: fake.world())

        XCTAssertEqual(preparation, .refused(.cliDidNotAnswer(command: "claude plugin update --help", reason: "timed out")))
        XCTAssertEqual(fake.changingRuns, [])
    }

    func testARefusedUpdateSaysWhyWithoutAsking() {
        let fake = outdatedFake()
        let flow = createFlow(fake, own: "0.2.0")
        flow.refresh(then: nil)
        fake.answers[updateHelp] = PluginCommandOutcome(end: .timedOut)
        answers = [true]

        flow.update()

        XCTAssertEqual(asked, [])
        XCTAssertEqual(informed.map(\.title), [SessionHandoffUpdateCopy.notUpdatedTitle])
        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertFalse(flow.row.isBusy)
    }

    func testQuitStopsTheNextCommandAtEveryStep() throws {
        let stops: [(why: String, at: String, notRun: String)] = [
            ("during the checks", refreshHelp, updateHelp),
            ("between the two commands", refresh, update),
            ("during the reading after", list, marketplaces),
        ]

        for (why, stopAt, notRun) in stops {
            let fake = outdatedFake()
            let work = SessionHandoffWork(world: fake.world(), center: NotificationCenter())
            let isAfterTheCommands = stopAt == list
            fake.whenRunning = { line in
                let key = FakePluginWorld.key(line.executable, line.arguments)
                guard key == stopAt, !isAfterTheCommands || fake.commands.contains(self.update) else { return }
                work.stop()
            }
            let flow = SessionHandoffFlow(
                own: "0.2.0",
                perform: { $0(work.world) },
                onMain: { $0() },
                ask: { _ in true },
                inform: { _, _ in },
                show: {}
            )
            flow.refresh(then: nil)

            flow.update()

            XCTAssertEqual(fake.commands.last, stopAt, why)
            XCTAssertEqual(fake.commands.filter { $0 == notRun }.count, notRun == marketplaces ? 3 : 0, why)
        }
    }
}
