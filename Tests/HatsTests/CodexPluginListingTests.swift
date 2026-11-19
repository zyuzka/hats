import XCTest
@testable import Hats

final class CodexPluginListingTests: XCTestCase {
    func testThePluginListIsReadFromItsObject() {
        let read = CodexPluginListing.findPlugins(in: CodexPluginCLISamples.listFromFolder.outcome)

        XCTAssertEqual(read, .success([
            CodexPluginRecord(
                id: "hats@hats",
                version: "0.1.0",
                isEnabled: true,
                path: CodexPluginCLISamples.pluginFolder
            ),
        ]))
        XCTAssertEqual(CodexPluginListing.findPlugins(in: CodexPluginCLISamples.listEmpty.outcome), .success([]))
    }

    func testAListThatIsAnArrayIsRefused() {
        let read = CodexPluginListing.findPlugins(in: FakePluginWorld.printed("[]"))

        XCTAssertEqual(read, .failure(.unreadable("its answer is not one JSON object with a list under installed")))
    }

    func testTheMarketplaceListKeepsTheSource() {
        let read = CodexPluginListing.findMarkets(in: CodexPluginCLISamples.marketsFolder.outcome)

        XCTAssertEqual(read, .success([
            CodexMarketRecord(name: "openai-curated", sourceType: nil, source: nil),
            CodexMarketRecord(name: "hats", sourceType: "local", source: CodexPluginCLISamples.worktree),
        ]))
    }

    func testTheSourceOfTheMarketplace() {
        func source(_ type: String?, _ text: String?) -> CodexPluginSource {
            CodexPluginProvenance.getSource([CodexMarketRecord(name: "hats", sourceType: type, source: text)])
        }

        XCTAssertEqual(CodexPluginProvenance.getSource([]), .absent)
        for text in [
            "https://github.com/zyuzka/hats.git",
            "https://github.com/Zyuzka/Hats",
            "zyuzka/hats",
            "git@github.com:zyuzka/hats.git",
        ] {
            XCTAssertEqual(source("git", text), .github, text)
        }
        XCTAssertEqual(source("local", "/somewhere/hats"), .folder("/somewhere/hats"))
        XCTAssertEqual(
            source("git", "https://github.com/zyuzka/hats-fork.git"),
            .foreign("the Codex marketplace named hats comes from https://github.com/zyuzka/hats-fork.git, not from "
                + "zyuzka/hats")
        )
        guard case .foreign = source(nil, nil) else { return XCTFail("no source is not ours") }
        guard case .foreign = source("local", "relative/path") else { return XCTFail("a relative folder is not ours") }
    }

    func testTheAnswersOfTheChangingCommands() {
        let plugin = CodexPluginListing.findPluginTrouble
        XCTAssertTrue(CodexPluginListing.getAnswer(of: CodexPluginCLISamples.addDone.outcome, findTrouble: plugin).isDone)
        XCTAssertTrue(CodexPluginListing.getAnswer(of: CodexPluginCLISamples.removeDone.outcome, findTrouble: plugin).isDone)
        XCTAssertTrue(CodexPluginListing.getAnswer(
            of: CodexPluginCLISamples.marketAddDone.outcome,
            findTrouble: CodexPluginListing.findMarketTrouble
        ).isDone)
        XCTAssertTrue(CodexPluginListing.getAnswer(
            of: CodexPluginCLISamples.upgradeDone.outcome,
            findTrouble: CodexPluginListing.findUpgradeTrouble
        ).isDone)

        let failed = CodexPluginListing.getAnswer(of: CodexPluginCLISamples.addNotFound.outcome, findTrouble: plugin)
        XCTAssertEqual(failed, PluginChangeAnswer(
            isDone: false,
            message: "exit code 1: Error: plugin `hats` was not found in marketplace `hats`"
        ))
    }

    func testAnUpgradeWithErrorsIsNotDone() {
        let outcome = FakePluginWorld.printed(#"{"selectedMarketplaces":["hats"],"upgradedRoots":[],"errors":["no net",3]}"#)

        let answer = CodexPluginListing.getAnswer(of: outcome, findTrouble: CodexPluginListing.findUpgradeTrouble)

        XCTAssertEqual(answer, PluginChangeAnswer(isDone: false, message: "it reported: no net; 3"))
    }

    func testTheCacheFolderOfTheCopy() {
        XCTAssertEqual(
            CodexPluginCopy.getCachePath(codexHome: CodexPluginCLISamples.codexHome, version: "0.1.0"),
            CodexPluginCLISamples.cache
        )
    }
}
