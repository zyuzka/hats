import XCTest
@testable import Hats

final class SessionHandoffListingTests: XCTestCase {
    func testTheIndentedListIsReadAsOneArray() throws {
        let read = SessionHandoffListing.findPlugins(in: PluginCLISamples.listGithubPluginAndFolder.outcome)

        XCTAssertEqual(try read.get().map(\.id), [
            "42crunch-api-security-testing@claude-plugins-official",
            "hats@hats",
        ])
    }

    func testAnEmptyListIsNotAListThatCouldNotBeRead() throws {
        let empty = SessionHandoffListing.findPlugins(in: PluginCLISamples.listEmpty.outcome)
        let failed = SessionHandoffListing.findPlugins(in: PluginCommandOutcome(end: .exited(1)))

        XCTAssertEqual(try empty.get(), [])
        guard case .failure = failed else { return XCTFail("a failed command is not an empty list") }
    }

    func testATruncatedListIsAnError() {
        var outcome = PluginCLISamples.listUserFromFolder.outcome
        outcome.isTruncated = true

        let read = SessionHandoffListing.findPlugins(in: outcome)

        guard case .failure(.unreadable(let reason)) = read else { return XCTFail("expected unreadable, got \(read)") }
        XCTAssertTrue(reason.contains("cut off"), reason)
    }

    func testOnlyTheFirstLineOfTheListIsNotEnough() {
        let firstLine = FakePluginWorld.printed("[\n")

        let read = SessionHandoffListing.findPlugins(in: firstLine)

        guard case .failure = read else { return XCTFail("half a list is not a list") }
    }

    func testAnEntryWithoutScopeMakesTheListUnreadable() {
        let read = SessionHandoffListing.findPlugins(in: FakePluginWorld.printed("[{\"id\": \"hats@hats\"}]"))

        guard case .failure = read else { return XCTFail("an entry without scope cannot be placed") }
    }

    func testTheMarketplaceListCarriesSourceRepoAndPath() throws {
        let read = SessionHandoffListing.findMarketplaces(in: PluginCLISamples.marketplacesGithubAndFolder.outcome)

        XCTAssertEqual(try read.get(), [
            MarketplaceRecord(
                name: "claude-plugins-official",
                source: "github",
                repo: "anthropics/claude-plugins-official",
                path: nil
            ),
            MarketplaceRecord(name: "hats", source: "directory", repo: nil, path: "/market"),
        ])
    }

    func testTheInstallAnswerIsItsLastJSONLine() {
        let earlier = "{\"outcome\": \"failed\", \"message\": \"an earlier line\"}\n"
        let outcome = FakePluginWorld.printed(earlier + "Cloning…\n" + PluginCLISamples.installFromFolder.stdout)

        let answer = SessionHandoffListing.getAnswer(of: outcome)

        XCTAssertEqual(answer, PluginChangeAnswer(isDone: true, message: "Successfully installed plugin: hats@hats (scope: user)"))
    }

    func testAnOkLineWithAFailingExitCodeIsNotDone() {
        let outcome = PluginCommandOutcome(end: .exited(1), stdout: Data(PluginCLISamples.installFromFolder.stdout.utf8))

        XCTAssertFalse(SessionHandoffListing.getAnswer(of: outcome).isDone)
    }

    func testAZeroExitWithoutJSONIsNotDone() {
        let answer = SessionHandoffListing.getAnswer(of: FakePluginWorld.printed("Installed.\n"))

        XCTAssertEqual(answer, PluginChangeAnswer(isDone: false, message: "its answer held no JSON result"))
    }

    func testAnAlreadyInstalledAnswerCountsAsDone() {
        XCTAssertTrue(SessionHandoffListing.getAnswer(of: PluginCLISamples.installAlreadyThere.outcome).isDone)
    }

    func testAFailedUninstallIsReportedFromItsJSONMessage() {
        let answer = SessionHandoffListing.getAnswer(of: PluginCLISamples.uninstallNotInstalled.outcome)

        XCTAssertEqual(answer, PluginChangeAnswer(
            isDone: false,
            message: "Plugin \"hats@hats\" not found in installed plugins"
        ))
    }

    func testTheOldHookIsMatchedOnlyOutsideThePlugin() {
        XCTAssertTrue(SessionHandoffOldHook.isHandoffStart("python3 -I \"$HOME/.claude/hooks/handoff.py\" start"))
        XCTAssertTrue(SessionHandoffOldHook.isHandoffStart("/usr/bin/env python3 /Users/someone/handoff.py start"))
        XCTAssertFalse(SessionHandoffOldHook.isHandoffStart(
            "sh \"${CLAUDE_PLUGIN_ROOT}/scripts/py.sh\" --quiet \"${CLAUDE_PLUGIN_ROOT}/scripts/handoff.py\" start"
        ))
        XCTAssertFalse(SessionHandoffOldHook.isHandoffStart("python3 \"$HOME/.claude/hooks/handoff.py\" save"))
        XCTAssertFalse(SessionHandoffOldHook.isHandoffStart("python3 my-handoff.py start"))
        XCTAssertFalse(SessionHandoffOldHook.isHandoffStart("echo start handoff.py"))
    }

    func testTheOldHookIsLookedForOnlyUnderSessionStart() {
        let root: [String: Any] = [
            "hooks": [
                "UserPromptSubmit": [
                    ["hooks": [["type": "command", "command": "python3 handoff.py start"]]],
                ],
                "SessionStart": [
                    ["hooks": [["type": "command", "command": "echo hello"]]],
                    "not a group",
                ],
            ],
        ]

        XCTAssertEqual(SessionHandoffOldHook.findHandoffStarts(in: root), [])
    }
}
