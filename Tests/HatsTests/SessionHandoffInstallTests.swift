import XCTest
@testable import Hats

struct NotReady: Error {}

final class SessionHandoffInstallTests: XCTestCase {
    private let install = FakePluginWorld.claude([
        "plugin",
        "install",
        "hats",
        "--marketplace",
        "zyuzka/hats",
        "--scope",
        "user",
        "--json",
    ])
    private let list = FakePluginWorld.claude(SessionHandoffSteps.listArguments)
    private let marketplaces = FakePluginWorld.claude(SessionHandoffSteps.marketplaceArguments)

    private func readyPlan(_ fake: FakePluginWorld) throws -> SessionHandoffPlan {
        guard case .ready(let plan, let face) = SessionHandoffSteps.getPreparation(in: fake.world()) else {
            XCTFail("the checks were expected to pass, so the consent window could open")
            throw NotReady()
        }
        XCTAssertEqual(face, .notInstalled(elsewhere: []))

        return plan
    }

    func testConsentInstallsOnceAndThenListsThePlugin() throws {
        let fake = FakePluginWorld()
        let plan = try readyPlan(fake)
        XCTAssertEqual(fake.changingRuns, [],
                       "before consent not one claude plugin command that changes anything may run")
        fake.answer(install, PluginCLISamples.installFromFolder)
        fake.queue(list, [
            PluginCLISamples.listEmpty.outcome,
            PluginCLISamples.listUserFromFolder.outcome,
        ])
        fake.queue(marketplaces, [
            PluginCLISamples.marketplacesEmpty.outcome,
            PluginCLISamples.marketplacesFolder.outcome,
        ])
        fake.runs = []

        let change = SessionHandoffSteps.getInstallChange(plan, in: fake.world())

        XCTAssertEqual(fake.commands, [list, marketplaces, install, list, marketplaces],
                       "after consent: the list read again, the install, then one reading of the list")
        XCTAssertNil(change.failure)
        XCTAssertNil(change.refusal)
        XCTAssertNil(change.notice)
        XCTAssertEqual(change.face, .installed(version: "0.1.0", folder: "/market", isEnabled: true, elsewhere: []))
        let installRun = try XCTUnwrap(fake.changingRuns.first)
        XCTAssertFalse(installRun.arguments.contains("-y"),
                       "a marketplace command is never confirmed on the user's behalf")
        XCTAssertFalse(installRun.arguments.contains("--yes"))
    }

    func testAFailedInstallIsReportedFromItsLastJSONLineAndNotRepeated() throws {
        let fake = FakePluginWorld()
        let plan = try readyPlan(fake)
        fake.answer(install, PluginCLISamples.installManifestMissing)
        fake.runs = []

        let change = SessionHandoffSteps.getInstallChange(plan, in: fake.world())

        XCTAssertEqual(change.failure, "Marketplace file not found at "
            + "/home/node/.claude/plugins/marketplaces/zyuzka-hats/.claude-plugin/marketplace.json")
        XCTAssertEqual(fake.commands.filter { $0 == install }.count, 1, "a failure is reported, not retried")
        XCTAssertEqual(change.face, .notInstalled(elsewhere: []))
    }

    func testAnInstallThatTimesOutStopsAndReadsTheListOnce() throws {
        let fake = FakePluginWorld()
        let plan = try readyPlan(fake)
        fake.answers[install] = PluginCommandOutcome(end: .timedOut)
        fake.runs = []

        let change = SessionHandoffSteps.getInstallChange(plan, in: fake.world())

        XCTAssertEqual(change.failure, "timed out")
        XCTAssertEqual(fake.commands, [list, marketplaces, install, list, marketplaces])
        XCTAssertEqual(fake.changingRuns.map(\.seconds), [120])
    }

    func testAListThatTimesOutAfterTheInstallLeavesTheStateUnknownWithoutRetrying() throws {
        let fake = FakePluginWorld()
        let plan = try readyPlan(fake)
        fake.answers[install] = PluginCommandOutcome(end: .timedOut)
        fake.queue(list, [
            PluginCLISamples.listEmpty.outcome,
            PluginCommandOutcome(end: .timedOut),
        ])
        fake.runs = []

        let change = SessionHandoffSteps.getInstallChange(plan, in: fake.world())

        XCTAssertEqual(fake.commands, [list, marketplaces, install, list], "no second reading and no rollback")
        guard case .unknown(let reason)? = change.face else {
            return XCTFail("expected unknown, got \(String(describing: change.face))")
        }
        XCTAssertTrue(reason.contains("timed out"), reason)
    }

    func testAnOldHookAddedAfterTheChecksStopsTheInstall() throws {
        let fake = FakePluginWorld()
        let plan = try readyPlan(fake)
        fake.files[FakePluginWorld.settings] = .read(Data(Self.settingsWithTheOldHook.utf8))
        fake.runs = []

        let change = SessionHandoffSteps.getInstallChange(plan, in: fake.world())

        XCTAssertEqual(fake.runs, [], "the old hook is checked again right before the install")
        guard case .oldHook(let file, _)? = change.refusal else { return XCTFail("expected the old hook") }
        XCTAssertEqual(file, FakePluginWorld.settings)
    }

    func testAnInstallThatTimesOutButIsListedIsReportedFromTheList() throws {
        let fake = FakePluginWorld()
        let plan = try readyPlan(fake)
        fake.answers[install] = PluginCommandOutcome(end: .timedOut)
        fake.queue(list, [
            PluginCLISamples.listEmpty.outcome,
            PluginCLISamples.listUserFromFolder.outcome,
        ])
        fake.queue(marketplaces, [
            PluginCLISamples.marketplacesEmpty.outcome,
            PluginCLISamples.marketplacesFolder.outcome,
        ])

        let change = SessionHandoffSteps.getInstallChange(plan, in: fake.world())

        XCTAssertNil(change.failure, "the list shows the plugin, so the outcome is not «not installed»")
        let notice = try XCTUnwrap(change.notice)
        XCTAssertTrue(notice.contains("did not answer cleanly (timed out)"), notice)
        XCTAssertTrue(notice.contains("Installed"), notice)
    }

    func testAnInstallAnsweringOkThatIsNotListedIsAFailure() throws {
        let fake = FakePluginWorld()
        let plan = try readyPlan(fake)
        fake.answer(install, PluginCLISamples.installFromFolder)

        let change = SessionHandoffSteps.getInstallChange(plan, in: fake.world())

        let failure = try XCTUnwrap(change.failure)
        XCTAssertTrue(failure.hasPrefix("claude plugin install answered ok, but the plugin list now reads: Not installed"),
                      failure)
    }

    func testAPluginInstalledWhileTheWindowWasOpenIsNotInstalledAgain() throws {
        let fake = FakePluginWorld()
        let plan = try readyPlan(fake)
        fake.answer(list, PluginCLISamples.listUserFromFolder)
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)

        let change = SessionHandoffSteps.getInstallChange(plan, in: fake.world())

        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertEqual(change.face, .installed(version: "0.1.0", folder: "/market", isEnabled: true, elsewhere: []))
        XCTAssertTrue(change.failure?.contains("changed while the window was open") == true)
    }

    func testAMarketplaceAddedWhileTheWindowWasOpenStopsAnInstallFromAnotherSource() throws {
        let fake = FakePluginWorld()
        let plan = try readyPlan(fake)
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)

        let change = SessionHandoffSteps.getInstallChange(plan, in: fake.world())

        XCTAssertEqual(plan.source, "zyuzka/hats")
        XCTAssertEqual(fake.changingRuns, [], "the plan said zyuzka/hats, the list now says the folder /market")
        XCTAssertNotNil(change.failure)
    }

    func testAPluginAlreadyInstalledFromAFolderIsShownWithThatFolderAndNotInstalledAgain() {
        let fake = FakePluginWorld()
        fake.answer(list, PluginCLISamples.listUserFromFolder)
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)

        let preparation = SessionHandoffSteps.getPreparation(in: fake.world())

        XCTAssertEqual(preparation, .settled(.installed(version: "0.1.0", folder: "/market", isEnabled: true, elsewhere: [])))
        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertTrue(SessionHandoffCopy.getStatus(.installed(version: "0.1.0", folder: "/market", isEnabled: true, elsewhere: []))
            .contains("from the folder /market"))
    }

    func testAFolderMarketplaceWithoutThePluginInstallsFromThatFolder() throws {
        let fake = FakePluginWorld()
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)

        let plan = try readyPlan(fake)

        XCTAssertEqual(plan.source, "/market",
                       "the user's own hats marketplace is reused, not shadowed by a second one from GitHub")
        XCTAssertEqual(plan.folder, "/market")
        XCTAssertEqual(plan.arguments, [
            "plugin",
            "install",
            "hats",
            "--marketplace",
            "/market",
            "--scope",
            "user",
            "--json",
        ])
    }

    func testTheConsentWindowNamesThePluginTheCommandAndTheSettingsFolder() throws {
        let fake = FakePluginWorld()
        let plan = try readyPlan(fake)

        let prompt = SessionHandoffPrompts.createInstall(plan)

        XCTAssertEqual(prompt.buttons, ["Install", "Cancel"])
        XCTAssertTrue(prompt.text.contains("claude plugin install hats --marketplace zyuzka/hats --scope user --json"))
        XCTAssertTrue(prompt.text.contains("hats@hats"))
        XCTAssertTrue(prompt.text.contains(FakePluginWorld.cli), "the window names which claude will run")
        XCTAssertTrue(prompt.text.contains("github.com/zyuzka/hats"))
        XCTAssertTrue(prompt.text.contains(FakePluginWorld.configFolder))
        XCTAssertTrue(prompt.text.contains(FakePluginWorld.homebrewPython))
        XCTAssertTrue(prompt.text.contains("new login shell"),
                      "without a live session python3 is found through the login shell, and the window says so")
    }

    static let settingsWithTheOldHook = """
    {"hooks": {"SessionStart": [{"matcher": "startup|clear", "hooks": [{"type": "command",
    "command": "python3 -I \\"$HOME/.claude/hooks/handoff.py\\" start"}]}]}}
    """
}
