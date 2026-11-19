import XCTest
@testable import Hats

extension FakePluginWorld {
    static func codex(_ arguments: [String]) -> String { key(CodexPluginCLISamples.codex, arguments) }

    static func withCodex() -> FakePluginWorld {
        let fake = FakePluginWorld()
        fake.executables.insert(CodexPluginCLISamples.codex)
        fake.answer(codex(CodexPluginSteps.listArguments), CodexPluginCLISamples.listEmpty)
        fake.answer(codex(CodexPluginSteps.marketListArguments), CodexPluginCLISamples.marketsEmpty)

        return fake
    }

    var codexCommands: [[String]] {
        runs.filter { $0.executable == CodexPluginCLISamples.codex }.map(\.arguments)
    }
}

final class CodexPluginFlowTests: XCTestCase {
    private let list = FakePluginWorld.codex(CodexPluginSteps.listArguments)
    private let markets = FakePluginWorld.codex(CodexPluginSteps.marketListArguments)
    private let add = FakePluginWorld.codex(CodexPluginSteps.addArguments)
    private let marketAdd = FakePluginWorld.codex(CodexPluginSteps.marketAddArguments)
    private let upgrade = FakePluginWorld.codex(CodexPluginSteps.upgradeArguments)
    private let remove = FakePluginWorld.codex(CodexPluginSteps.removeArguments)
    private let copyKey = CodexPluginCLISamples.cache + "=" + CodexPluginCLISamples.pluginFolder

    private var answers: [Bool] = []
    private var asked: [HatPrompt] = []
    private var informed: [(title: String, text: String)] = []
    private var journaled: [String] = []

    private func createFlow(_ fake: FakePluginWorld, own: String = "0.1.0") -> CodexPluginFlow {
        CodexPluginFlow(
            own: own,
            perform: { work in work(fake.world()) },
            onMain: { $0() },
            ask: { [unowned self] prompt in
                asked.append(prompt)
                return answers.isEmpty ? false : answers.removeFirst()
            },
            inform: { [unowned self] title, text in informed.append((title, text)) },
            show: {},
            journal: { [unowned self] operation, _ in journaled.append(operation) }
        )
    }

    private func folderFake(copy: CodexCopyState) -> FakePluginWorld {
        let fake = FakePluginWorld.withCodex()
        fake.answer(list, CodexPluginCLISamples.listFromFolder)
        fake.answer(markets, CodexPluginCLISamples.marketsFolder)
        fake.copies[copyKey] = copy

        return fake
    }

    private func gitHubFake(version: String) -> FakePluginWorld {
        let fake = FakePluginWorld.withCodex()
        fake.answer(list, CodexPluginCLISamples.listFromGitHub(version: version))
        fake.answer(markets, CodexPluginCLISamples.marketsGitHub)

        return fake
    }

    func testInstallWithoutAMarketplaceAddsItThenThePlugin() {
        let fake = FakePluginWorld.withCodex()
        fake.answer(marketAdd, CodexPluginCLISamples.marketAddDone)
        fake.answer(add, CodexPluginCLISamples.addDone)
        fake.queue(list, [
            CodexPluginCLISamples.listEmpty.outcome,
            CodexPluginCLISamples.listEmpty.outcome,
            CodexPluginCLISamples.listEmpty.outcome,
            CodexPluginCLISamples.listFromGitHub(version: "0.1.0").outcome,
        ])
        fake.queue(markets, [
            CodexPluginCLISamples.marketsEmpty.outcome,
            CodexPluginCLISamples.marketsEmpty.outcome,
            CodexPluginCLISamples.marketsEmpty.outcome,
            CodexPluginCLISamples.marketsGitHub.outcome,
        ])
        let flow = createFlow(fake)
        flow.refresh(then: nil)
        answers = [true]

        flow.install()

        XCTAssertEqual(asked.map(\.title), ["Install the Codex plugin?"])
        XCTAssertEqual(fake.changingRuns.map(\.arguments), [
            CodexPluginSteps.marketAddArguments,
            CodexPluginSteps.addArguments,
        ])
        XCTAssertEqual(flow.row.face, .installed(version: "0.1.0", isEnabled: true))
        XCTAssertEqual(informed.map(\.title), ["Installed"])
        XCTAssertTrue(informed.first?.text.contains(CodexPluginText.trustNote) == true)
        XCTAssertEqual(journaled, ["codexPlugin.installing", "codexPlugin.changed"])
    }

    func testInstallWithOurMarketplaceRunsOnlyThePluginAdd() {
        let fake = FakePluginWorld.withCodex()
        fake.answer(markets, CodexPluginCLISamples.marketsGitHub)
        fake.answer(add, CodexPluginCLISamples.addDone)
        fake.queue(list, [
            CodexPluginCLISamples.listEmpty.outcome,
            CodexPluginCLISamples.listEmpty.outcome,
            CodexPluginCLISamples.listEmpty.outcome,
            CodexPluginCLISamples.listFromGitHub(version: "0.1.0").outcome,
        ])
        let flow = createFlow(fake)
        flow.refresh(then: nil)
        answers = [true]

        flow.install()

        XCTAssertEqual(fake.changingRuns.map(\.arguments), [CodexPluginSteps.addArguments])
        XCTAssertEqual(informed.map(\.title), ["Installed"])
    }

    func testAFreshInstallOffersOnlyRemove() {
        let fake = gitHubFake(version: "0.1.0")
        let flow = createFlow(fake)

        flow.refresh(then: nil)

        XCTAssertEqual(flow.row.face, .installed(version: "0.1.0", isEnabled: true))
        XCTAssertNil(flow.row.offer)
        XCTAssertFalse(flow.row.face.canInstall)
        XCTAssertFalse(flow.row.face.canRefresh)
        XCTAssertTrue(flow.row.face.canRemove)
        XCTAssertEqual(CodexPluginText.getStatus(flow.row.face), "Installed, 0.1.0, from github.com/zyuzka/hats.")
    }

    func testAnOldInstallFromGitHubUpgradesTheMarketplaceThenAddsThePlugin() {
        let fake = gitHubFake(version: "0.1.0")
        fake.answer(upgrade, CodexPluginCLISamples.upgradeDone)
        fake.answer(add, CodexPluginCLISamples.addDone)
        let flow = createFlow(fake, own: "0.2.0")
        flow.refresh(then: nil)
        fake.queue(list, [
            CodexPluginCLISamples.listFromGitHub(version: "0.1.0").outcome,
            CodexPluginCLISamples.listFromGitHub(version: "0.1.0").outcome,
            CodexPluginCLISamples.listFromGitHub(version: "0.2.0").outcome,
        ])
        answers = [true]

        XCTAssertEqual(flow.row.offer, SessionHandoffOffer(installed: "0.1.0", own: "0.2.0"))
        flow.update()

        XCTAssertEqual(asked.map(\.title), ["Update the Codex plugin?"])
        XCTAssertEqual(fake.changingRuns.map(\.arguments), [
            CodexPluginSteps.upgradeArguments,
            CodexPluginSteps.addArguments,
        ])
        XCTAssertEqual(informed.map(\.title), ["Updated"])
        XCTAssertTrue(informed.first?.text.contains(CodexPluginText.trustNote) == true)
        XCTAssertEqual(journaled, ["codexPlugin.updating", "codexPlugin.changed"])
        XCTAssertNil(flow.row.offer)
    }

    func testAnUpdateGitHubDoesNotOfferYetIsReportedAsNotUpdated() {
        let fake = gitHubFake(version: "0.1.0")
        fake.answer(upgrade, CodexPluginCLISamples.upgradeDone)
        fake.answer(add, CodexPluginCLISamples.addDone)
        let flow = createFlow(fake, own: "0.2.0")
        flow.refresh(then: nil)
        answers = [true]

        flow.update()

        XCTAssertEqual(informed.map(\.title), ["The Codex plugin was not updated"])
        XCTAssertEqual(journaled, ["codexPlugin.updating", "codexPlugin.notChanged"])
    }

    func testAFolderWhoseCopyMatchesOffersNeitherUpdateNorRefresh() {
        let fake = folderFake(copy: .same)
        let flow = createFlow(fake, own: "0.2.0")

        flow.refresh(then: nil)

        XCTAssertEqual(flow.row.face, .fromFolder(
            version: "0.1.0",
            folder: CodexPluginCLISamples.pluginFolder,
            copy: .same
        ))
        XCTAssertNil(flow.row.offer, "a folder install is the developer's: Hats does not offer GitHub's version")
        XCTAssertFalse(flow.row.face.canRefresh)
        XCTAssertTrue(CodexPluginText.getStatus(flow.row.face).contains("from a folder"))
        XCTAssertEqual(fake.compared, [copyKey])
    }

    func testAStaleCopyIsRefreshedByAddingThePluginAgain() {
        let fake = folderFake(copy: .differs("scripts/window.py differs"))
        fake.answer(add, CodexPluginCLISamples.addDone)
        let flow = createFlow(fake)
        flow.refresh(then: nil)
        XCTAssertTrue(flow.row.face.canRefresh)
        answers = [true]
        fake.whenRunning = { [unowned fake, copyKey] line in
            if line.arguments == CodexPluginSteps.addArguments { fake.copies[copyKey] = .same }
        }

        flow.refreshCopy()

        XCTAssertEqual(asked.map(\.title), ["Refresh the Codex plugin?"])
        XCTAssertEqual(fake.changingRuns.map(\.arguments), [CodexPluginSteps.addArguments])
        XCTAssertEqual(informed.map(\.title), ["Refreshed"])
        XCTAssertTrue(informed.first?.text.contains(CodexPluginText.trustNote) == true)
        XCTAssertEqual(journaled, ["codexPlugin.refreshing", "codexPlugin.changed"])
        XCTAssertFalse(flow.row.face.canRefresh)
    }

    func testAnUnreadableCopyGivesNoRefreshAndNamesTheReason() {
        let fake = folderFake(copy: .unreadable("scripts is larger than 4 MB"))
        let flow = createFlow(fake)

        flow.refresh(then: nil)

        XCTAssertFalse(flow.row.face.canRefresh)
        XCTAssertTrue(CodexPluginText.getStatus(flow.row.face).contains("scripts is larger than 4 MB"))
    }

    func testAForeignMarketplaceIsNotOursAndOffersNothing() {
        let fake = FakePluginWorld.withCodex()
        fake.answer(markets, CodexPluginCLISamples.markets(
            name: "hats",
            sourceType: "git",
            source: "https://github.com/someone-else/hats.git"
        ))
        let flow = createFlow(fake)

        flow.refresh(then: nil)

        guard case .notOurs(let reason) = flow.row.face else { return XCTFail("\(flow.row.face)") }
        XCTAssertTrue(reason.contains("someone-else"))
        XCTAssertFalse(flow.row.face.canInstall || flow.row.face.canRemove || flow.row.face.canRefresh)
        XCTAssertTrue(CodexPluginText.getStatus(flow.row.face).hasPrefix("Not ours: "))
    }

    func testAnotherPluginNamedHatsIsNotOurs() {
        let fake = FakePluginWorld.withCodex()
        let other = CodexPluginCLISamples.listFromFolder.stdout.replacingOccurrences(of: "hats@hats", with: "hats@other")
        fake.answers[list] = FakePluginWorld.printed(other)
        let flow = createFlow(fake)

        flow.refresh(then: nil)

        XCTAssertEqual(flow.row.face, .notOurs("hats@other is installed in Codex: another plugin under the name hats"))
    }

    func testWithoutCodexTheRowSaysSoAndNothingRuns() {
        let fake = FakePluginWorld()
        let flow = createFlow(fake)

        flow.refresh(then: nil)

        XCTAssertEqual(flow.row.face, .noCodex)
        XCTAssertTrue(CodexPluginText.getStatus(.noCodex).hasPrefix("Codex not found"))
        XCTAssertFalse(flow.row.face.canInstall || flow.row.face.canRemove || flow.row.face.canRefresh)
        XCTAssertEqual(fake.codexCommands, [])
        XCTAssertEqual(journaled, [], "a launch without Codex writes nothing to the journal")
        XCTAssertEqual(informed.count, 0, "no window opens without a button")
    }

    func testLosingCodexAfterItWasSeenIsJournaled() {
        let fake = gitHubFake(version: "0.1.0")
        let flow = createFlow(fake)
        flow.refresh(then: nil)
        fake.executables = []

        flow.refresh(then: nil)

        XCTAssertEqual(flow.row.face, .noCodex)
        XCTAssertEqual(journaled, ["codexPlugin.refused"])
    }

    func testALocalInstallWithoutAPluginFolderComparesNothing() {
        let fake = FakePluginWorld.withCodex()
        let bare = CodexPluginCLISamples.listFromFolder.stdout
            .replacingOccurrences(of: "\"path\": \"/Users/someone/projects/hats/codex-plugin\"", with: "\"id\": \"x\"")
        fake.answers[list] = FakePluginWorld.printed(bare)
        fake.answer(markets, CodexPluginCLISamples.marketsFolder)
        let flow = createFlow(fake)

        flow.refresh(then: nil)

        guard case .fromFolder(_, _, .unreadable(let reason)) = flow.row.face else { return XCTFail("\(flow.row.face)") }
        XCTAssertTrue(reason.contains("Codex lists no plugin folder"))
        XCTAssertFalse(flow.row.face.canRefresh)
        XCTAssertEqual(fake.compared, [], "the marketplace root is not compared with the cache")
    }

    func testPressingAButtonWithNothingToDoUsesANeutralTitle() {
        let fake = gitHubFake(version: "0.1.0")
        let flow = createFlow(fake, own: "0.2.0")
        flow.refresh(then: nil)
        fake.answer(list, CodexPluginCLISamples.listFromGitHub(version: "0.2.0"))

        flow.update()

        XCTAssertEqual(informed.map(\.title), [CodexPluginText.nothingToDoTitle])
        XCTAssertTrue(informed.first?.text.hasPrefix("Nothing to do. ") == true)
        XCTAssertEqual(asked, [])
        XCTAssertEqual(fake.changingRuns, [])
    }

    func testAListThatChangedWhileTheWindowWasOpenRunsNothing() {
        let fake = FakePluginWorld.withCodex()
        let flow = createFlow(fake)
        flow.refresh(then: nil)
        answers = [true]
        fake.queue(list, [
            CodexPluginCLISamples.listEmpty.outcome,
            CodexPluginCLISamples.listFromGitHub(version: "0.1.0").outcome,
        ])
        fake.answer(markets, CodexPluginCLISamples.marketsGitHub)

        flow.install()

        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertEqual(informed.map(\.title), ["The Codex plugin was not installed"])
        XCTAssertTrue(informed.first?.text.hasPrefix("Nothing was changed: the Codex plugin list changed") == true)
        XCTAssertEqual(journaled, ["codexPlugin.installing", "codexPlugin.notChanged"])
    }

    func testAFailedReadBeforeRunningIsReportedAsThatFailure() {
        let fake = FakePluginWorld.withCodex()
        let flow = createFlow(fake)
        flow.refresh(then: nil)
        answers = [true]
        fake.queue(list, [
            CodexPluginCLISamples.listEmpty.outcome,
            PluginCommandOutcome(end: .timedOut),
        ])

        flow.install()

        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertEqual(informed.map(\.title), ["The Codex plugin was not installed"])
        let text = informed.first?.text ?? ""
        XCTAssertTrue(text.contains("The plugin list of Codex could not be read: timed out"), text)
        XCTAssertFalse(text.contains("changed while the window was open"))
    }

    func testAnUncleanAnswerWithThePluginListedIsInstalled() {
        let fake = FakePluginWorld.withCodex()
        fake.answer(markets, CodexPluginCLISamples.marketsGitHub)
        fake.answers[add] = PluginCommandOutcome(end: .timedOut)
        fake.queue(list, [
            CodexPluginCLISamples.listEmpty.outcome,
            CodexPluginCLISamples.listEmpty.outcome,
            CodexPluginCLISamples.listEmpty.outcome,
            CodexPluginCLISamples.listFromGitHub(version: "0.1.0").outcome,
        ])
        let flow = createFlow(fake)
        flow.refresh(then: nil)
        answers = [true]

        flow.install()

        XCTAssertEqual(informed.map(\.title), ["Installed"])
        XCTAssertTrue(informed.first?.text.contains("codex plugin add hats@hats did not answer cleanly (timed out)") == true)
        XCTAssertEqual(journaled, ["codexPlugin.installing", "codexPlugin.changed"])
    }

    func testAGitHubVersionBelowOursStillCountsAsUpdated() {
        let fake = gitHubFake(version: "0.1.0")
        fake.answer(upgrade, CodexPluginCLISamples.upgradeDone)
        fake.answer(add, CodexPluginCLISamples.addDone)
        let flow = createFlow(fake, own: "0.3.0")
        flow.refresh(then: nil)
        fake.queue(list, [
            CodexPluginCLISamples.listFromGitHub(version: "0.1.0").outcome,
            CodexPluginCLISamples.listFromGitHub(version: "0.1.0").outcome,
            CodexPluginCLISamples.listFromGitHub(version: "0.2.0").outcome,
        ])
        answers = [true]

        flow.update()

        XCTAssertEqual(informed.map(\.title), ["Updated"])
        XCTAssertEqual(journaled, ["codexPlugin.updating", "codexPlugin.changed"])
        XCTAssertEqual(flow.row.offer, SessionHandoffOffer(installed: "0.2.0", own: "0.3.0"))
    }

    func testAFailingOrTimedOutListIsAReasonInTheRow() {
        for outcome in [
            CodexPluginCLISamples.upgradeNotGit.outcome,
            PluginCommandOutcome(end: .timedOut),
        ] {
            let fake = FakePluginWorld.withCodex()
            fake.answers[list] = outcome
            journaled = []
            let flow = createFlow(fake)

            flow.refresh(then: nil)

            guard case .unknown(let reason) = flow.row.face else { return XCTFail("\(flow.row.face)") }
            XCTAssertTrue(reason.hasPrefix("The plugin list of Codex could not be read"))
            XCTAssertEqual(journaled, ["codexPlugin.refused"])
            XCTAssertEqual(informed.count, 0)
        }
    }

    func testAFailedPluginAddIsReportedWithCodexsReason() {
        let fake = FakePluginWorld.withCodex()
        fake.answer(marketAdd, CodexPluginCLISamples.marketAddNoManifest)
        let flow = createFlow(fake)
        flow.refresh(then: nil)
        answers = [true]

        flow.install()

        XCTAssertEqual(fake.changingRuns.map(\.arguments), [CodexPluginSteps.marketAddArguments],
                       "after the marketplace add failed the plugin add does not run")
        XCTAssertEqual(informed.map(\.title), ["The Codex plugin was not installed"])
        XCTAssertTrue(informed.first?.text.contains("does not contain a supported manifest") == true)
        XCTAssertEqual(journaled, ["codexPlugin.installing", "codexPlugin.notChanged"])
    }

    func testRemoveRunsOnlyThePluginRemove() {
        let fake = gitHubFake(version: "0.1.0")
        fake.answer(remove, CodexPluginCLISamples.removeDone)
        let flow = createFlow(fake)
        flow.refresh(then: nil)
        fake.queue(list, [
            CodexPluginCLISamples.listFromGitHub(version: "0.1.0").outcome,
            CodexPluginCLISamples.listFromGitHub(version: "0.1.0").outcome,
            CodexPluginCLISamples.listEmpty.outcome,
        ])
        answers = [true]

        flow.remove()

        XCTAssertEqual(fake.changingRuns.map(\.arguments), [CodexPluginSteps.removeArguments])
        XCTAssertEqual(flow.row.face, .notInstalled)
        XCTAssertEqual(informed.map(\.title), ["Removed"])
        XCTAssertFalse(informed.first?.text.contains(CodexPluginText.trustNote) == true)
        XCTAssertEqual(journaled, ["codexPlugin.removing", "codexPlugin.changed"])
    }

    func testCancelInAnyWindowRunsNoChangingCommand() {
        let cases: [(FakePluginWorld, String, (CodexPluginFlow) -> Void)] = [
            (FakePluginWorld.withCodex(), "0.1.0", { $0.install() }),
            (gitHubFake(version: "0.1.0"), "0.2.0", { $0.update() }),
            (folderFake(copy: .differs("x differs")), "0.1.0", { $0.refreshCopy() }),
            (gitHubFake(version: "0.1.0"), "0.1.0", { $0.remove() }),
        ]
        for (fake, own, press) in cases {
            asked = []
            answers = [false]
            journaled = []
            let flow = createFlow(fake, own: own)
            flow.refresh(then: nil)

            press(flow)

            XCTAssertEqual(asked.count, 1)
            XCTAssertEqual(fake.changingRuns, [])
            XCTAssertEqual(journaled, [])
            XCTAssertFalse(flow.row.isBusy)
        }
    }

    func testEveryCommandIsOneOfTheListedCodexCommands() {
        let allowed = [
            CodexPluginSteps.listArguments,
            CodexPluginSteps.marketListArguments,
            CodexPluginSteps.marketAddArguments,
            CodexPluginSteps.upgradeArguments,
            CodexPluginSteps.addArguments,
            CodexPluginSteps.removeArguments,
        ]
        let fake = gitHubFake(version: "0.1.0")
        fake.answer(upgrade, CodexPluginCLISamples.upgradeDone)
        fake.answer(add, CodexPluginCLISamples.addDone)
        fake.answer(remove, CodexPluginCLISamples.removeDone)
        let flow = createFlow(fake, own: "0.2.0")
        answers = [true, true]
        flow.refresh(then: nil)
        flow.update()
        flow.remove()

        XCTAssertFalse(fake.codexCommands.isEmpty)
        for arguments in fake.codexCommands {
            XCTAssertTrue(allowed.contains(arguments), arguments.joined(separator: " "))
        }
        for line in fake.runs where line.executable == CodexPluginCLISamples.codex {
            XCTAssertEqual(line.environment["CODEX_HOME"], CodexPluginCLISamples.codexHome)
        }
    }

    func testThePromptNamesTheCommandsItRuns() {
        let fake = FakePluginWorld.withCodex()
        let flow = createFlow(fake)
        flow.refresh(then: nil)

        flow.install()

        let text = asked.first?.text ?? ""
        XCTAssertTrue(text.contains("codex plugin marketplace add zyuzka/hats --json\ncodex plugin add hats@hats --json"))
        XCTAssertTrue(text.contains("CODEX_HOME=\(CodexPluginCLISamples.codexHome)"))
        XCTAssertTrue(text.contains(CodexPluginText.trustNote))
        XCTAssertEqual(asked.first?.buttons, ["Install", "Cancel"])
    }
}
