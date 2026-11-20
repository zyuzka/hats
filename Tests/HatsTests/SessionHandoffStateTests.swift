import XCTest
@testable import Hats

final class SessionHandoffStateTests: XCTestCase {
    private let list = FakePluginWorld.claude(SessionHandoffSteps.listArguments)
    private let marketplaces = FakePluginWorld.claude(SessionHandoffSteps.marketplaceArguments)
    private let uninstall = FakePluginWorld.claude(SessionHandoffSteps.removeArguments)

    private static let projectRecord = PluginRecord(
        id: "hats@hats",
        scope: "project",
        version: "0.1.0",
        projectPath: "/tmp/proj",
        isEnabled: true
    )

    private static func marketplacesNamedHats(_ entry: String) -> PluginCommandOutcome {
        FakePluginWorld.printed("[\n  {\n    \"name\": \"hats\",\n" + entry + "\n  }\n]\n")
    }

    func testAHatsMarketplaceFromAnotherRepositoryIsNotOursAndNothingIsInstalled() {
        let fake = FakePluginWorld()
        fake.answers[marketplaces] = Self.marketplacesNamedHats(
            "    \"source\": \"github\",\n    \"repo\": \"someone-else/hats\""
        )

        let preparation = SessionHandoffSteps.getPreparation(in: fake.world())

        XCTAssertEqual(preparation, .settled(.notOurs(
            "the marketplace named hats comes from someone-else/hats, not from zyuzka/hats"
        )))
        XCTAssertEqual(fake.changingRuns, [])
    }

    func testOurGitHubMarketplaceIsRecognisedWhateverTheLetterCase() {
        let source = SessionHandoffProvenance.getSource([
            MarketplaceRecord(name: "hats", source: "github", repo: "Zyuzka/Hats", path: nil),
        ])

        XCTAssertEqual(source, .github)
    }

    func testAnotherPluginNamedHatsIsNotOurs() {
        let face = SessionHandoffProvenance.getFace(
            plugins: [
                PluginRecord(
                    id: "hats@elsewhere",
                    scope: "user",
                    version: "2.0.0",
                    projectPath: nil,
                    isEnabled: true
                ),
            ],
            source: .absent
        )

        XCTAssertEqual(face, .notOurs("hats@elsewhere is installed: another plugin under the name hats"))
        XCTAssertFalse(face.canInstall)
        XCTAssertFalse(face.canRemove)
    }

    func testOurPluginWithoutAKnownMarketplaceCannotBeToldApart() {
        let face = SessionHandoffProvenance.getFace(
            plugins: [
                PluginRecord(
                    id: "hats@hats",
                    scope: "user",
                    version: "0.1.0",
                    projectPath: nil,
                    isEnabled: true
                ),
            ],
            source: .absent
        )

        guard case .notOurs = face else { return XCTFail("expected notOurs, got \(face)") }
        XCTAssertFalse(face.canRemove)
    }

    func testAMarketplaceListThatCannotBeReadLeavesTheOriginUnknownAndInstallsNothing() {
        let fake = FakePluginWorld()
        fake.answers[marketplaces] = PluginCommandOutcome(end: .timedOut)

        let preparation = SessionHandoffSteps.getPreparation(in: fake.world())

        guard case .settled(.unknown(let reason)) = preparation else {
            return XCTFail("expected an unknown origin, got \(preparation)")
        }
        XCTAssertTrue(reason.contains("timed out"), reason)
        XCTAssertEqual(fake.changingRuns, [])
    }

    func testAListThatTimesOutIsUnknownAndReadOnce() {
        let fake = FakePluginWorld()
        fake.answers[list] = PluginCommandOutcome(end: .timedOut)

        let face = SessionHandoffSteps.findFace(in: fake.world())

        guard case .unknown(let reason) = face else { return XCTFail("expected unknown, got \(face)") }
        XCTAssertTrue(reason.contains("timed out"), reason)
        XCTAssertEqual(fake.commands.filter { $0 == list }.count, 1)
        XCTAssertFalse(fake.commands.contains(marketplaces))
    }

    func testAProjectInstallationIsShownApartAndNotOfferedForRemoval() {
        let fake = FakePluginWorld()
        fake.answer(list, PluginCLISamples.listProjectScope)
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)

        let face = SessionHandoffSteps.findFace(in: fake.world())

        XCTAssertEqual(face, .notInstalled(elsewhere: [Self.projectRecord]))
        XCTAssertFalse(face.canRemove)
        XCTAssertTrue(SessionHandoffCopy.getStatus(face).contains("project scope in /tmp/proj"))
    }

    func testRemoveTouchesNothingWhenOnlyAProjectInstallationExists() {
        let fake = FakePluginWorld()
        fake.answer(list, PluginCLISamples.listProjectScope)
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)

        let change = SessionHandoffSteps.getRemoveChange(
            folder: FakePluginWorld.configFolder,
            in: fake.world()
        )

        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertNotNil(change.failure)
    }

    func testRemoveUninstallsTheUserScopeKeepingDataAndThenListsAgain() {
        let fake = FakePluginWorld()
        fake.queue(list, [
            PluginCLISamples.listUserFromFolder.outcome,
            PluginCLISamples.listEmpty.outcome,
        ])
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)
        fake.answer(uninstall, PluginCLISamples.uninstallDone)

        let change = SessionHandoffSteps.getRemoveChange(
            folder: FakePluginWorld.configFolder,
            in: fake.world()
        )

        XCTAssertEqual(fake.changingRuns.map(\.arguments), [[
            "plugin",
            "uninstall",
            "hats@hats",
            "--scope",
            "user",
            "--keep-data",
            "--json",
        ]])
        XCTAssertEqual(fake.commands.suffix(3), [uninstall, list, marketplaces])
        XCTAssertNil(change.failure)
        XCTAssertEqual(change.face, .notInstalled(elsewhere: []))
        XCTAssertFalse(fake.commands.contains { $0.contains("marketplace remove") }, "the marketplace stays")
    }

    func testAFailedRemoveIsReportedFromItsJSONLine() {
        let fake = FakePluginWorld()
        fake.answer(list, PluginCLISamples.listUserFromFolder)
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)
        fake.answer(uninstall, PluginCLISamples.uninstallEnabledAtProjectScope)

        let change = SessionHandoffSteps.getRemoveChange(
            folder: FakePluginWorld.configFolder,
            in: fake.world()
        )

        XCTAssertEqual(change.failure, "Plugin \"hats@hats\" is enabled at project scope (.claude/settings.json, "
            + "shared with your team). To disable just for you: claude plugin disable hats@hats --scope local")
        XCTAssertEqual(fake.commands.filter { $0 == uninstall }.count, 1)
    }

    func testARemoveThatTimesOutButIsGoneFromTheListIsReportedFromTheList() throws {
        let fake = FakePluginWorld()
        fake.queue(list, [
            PluginCLISamples.listUserFromFolder.outcome,
            PluginCLISamples.listEmpty.outcome,
        ])
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)
        fake.answers[uninstall] = PluginCommandOutcome(end: .timedOut)

        let change = SessionHandoffSteps.getRemoveChange(
            folder: FakePluginWorld.configFolder,
            in: fake.world()
        )

        XCTAssertNil(change.failure)
        let notice = try XCTUnwrap(change.notice)
        XCTAssertTrue(notice.contains("claude plugin uninstall did not answer cleanly (timed out)"), notice)
        XCTAssertEqual(change.face, .notInstalled(elsewhere: []))
    }

    func testASwitchedOffPluginIsShownAsOffAndCanStillBeRemoved() {
        let fake = FakePluginWorld()
        let recorded = PluginCLISamples.listUserFromFolder.stdout
        XCTAssertTrue(recorded.contains("\"enabled\": true"))
        fake.answers[list] = FakePluginWorld.printed(recorded.replacingOccurrences(
            of: "\"enabled\": true",
            with: "\"enabled\": false"
        ))
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)

        let face = SessionHandoffSteps.findFace(in: fake.world())

        XCTAssertEqual(face, .installed(version: "0.1.0", folder: "/market", isEnabled: false, elsewhere: []))
        XCTAssertTrue(SessionHandoffCopy.getStatus(face).contains("claude plugin enable hats@hats"))
        XCTAssertTrue(face.canRemove)
    }

    func testThePluginFromGitHubIsInstalledWithoutAFolderAndCanBeRemoved() {
        let fake = FakePluginWorld()
        fake.queue(list, [
            PluginCLISamples.listUserFromGitHub.outcome,
            PluginCLISamples.listUserFromGitHub.outcome,
            PluginCLISamples.listEmpty.outcome,
        ])
        fake.answer(marketplaces, PluginCLISamples.marketplacesHatsFromGitHub)
        fake.answer(uninstall, PluginCLISamples.uninstallDone)

        let face = SessionHandoffSteps.findFace(in: fake.world())
        let change = SessionHandoffSteps.getRemoveChange(
            folder: FakePluginWorld.configFolder,
            in: fake.world()
        )

        XCTAssertEqual(face, .installed(version: "0.1.0", folder: nil, isEnabled: true, elsewhere: []))
        XCTAssertTrue(face.canRemove)
        XCTAssertTrue(SessionHandoffCopy.getStatus(face).contains("from github.com/zyuzka/hats"))
        XCTAssertEqual(fake.changingRuns.map(\.arguments), [SessionHandoffSteps.removeArguments])
        XCTAssertEqual(change.face, .notInstalled(elsewhere: []))
    }

    func testInstallIsOfferedOnlyWhereNothingOfOursIsInstalled() {
        XCTAssertTrue(SessionHandoffFace.notInstalled(elsewhere: []).canInstall)
        XCTAssertTrue(SessionHandoffFace.unknown("timed out").canInstall)
        XCTAssertFalse(SessionHandoffFace.unread.canInstall)
        XCTAssertFalse(SessionHandoffFace.installed(version: nil, folder: nil, isEnabled: true, elsewhere: []).canInstall)
        XCTAssertFalse(SessionHandoffFace.notOurs("another plugin").canInstall)
    }

    func testTheRemoveWindowNamesTheCommandAndWhatStays() {
        let prompt = SessionHandoffPrompts.createRemove(folder: FakePluginWorld.configFolder)

        XCTAssertEqual(prompt.buttons, ["Remove", "Cancel"])
        XCTAssertTrue(prompt.text.contains("claude plugin uninstall hats@hats --scope user --keep-data --json"))
        XCTAssertTrue(prompt.text.contains("marketplace stays"))
        XCTAssertTrue(prompt.text.contains("settings folder \(FakePluginWorld.configFolder)"))
    }
}
