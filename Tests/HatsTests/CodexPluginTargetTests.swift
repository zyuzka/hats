import AppKit
import XCTest
@testable import Hats

final class CodexPluginTargetTests: XCTestCase {
    private let shellKey = FakePluginWorld.key(FakePluginWorld.shell, ["-lc", CodexPluginTargets.printPath])

    func testCodexInAKnownFolderIsFoundWithoutAShell() {
        let fake = FakePluginWorld()
        fake.executables = ["/usr/local/bin/codex"]

        let target = CodexPluginTargets.find(in: fake.world())

        XCTAssertEqual(target?.cli, "/usr/local/bin/codex")
        XCTAssertEqual(target?.environment["PATH"], "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                       "codex is a node script: its own folder comes first so env finds node")
        XCTAssertEqual(target?.codexHome, "/Users/someone/.codex")
        XCTAssertEqual(target?.environment["CODEX_HOME"], "/Users/someone/.codex")
        XCTAssertEqual(fake.runs, [])
    }

    func testTheKnownFoldersAreLookedAtInOrder() {
        let fake = FakePluginWorld()
        fake.executables = ["/opt/homebrew/bin/codex", "/Users/someone/.local/bin/codex"]

        XCTAssertEqual(CodexPluginTargets.find(in: fake.world())?.cli, "/opt/homebrew/bin/codex")
        XCTAssertEqual(CodexPluginTargets.getKnownFolders(home: "/h"), [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/h/.local/bin",
        ])
    }

    func testOtherwiseThePathOfALoginShellIsSearched() {
        let fake = FakePluginWorld()
        fake.executables = ["/Users/someone/.nvm/versions/node/v22/bin/codex"]
        fake.answers[shellKey] = FakePluginWorld.printed("\n__HATS_PATH__/Users/someone/.nvm/versions/node/v22/bin:/usr/bin")

        let target = CodexPluginTargets.find(in: fake.world())

        XCTAssertEqual(target?.cli, "/Users/someone/.nvm/versions/node/v22/bin/codex")
        XCTAssertEqual(target?.environment["PATH"], "/Users/someone/.nvm/versions/node/v22/bin:/usr/bin",
                       "the codex folder is already on the PATH, so it is not added twice")
    }

    func testTextAProfilePrintsBeforeThePathIsSkipped() {
        let printed = "Welcome!\n__HATS_PATH__ said by a profile\n__HATS_PATH__/opt/bin:/usr/bin\n"

        XCTAssertEqual(CodexPluginTargets.getPath(fromShellOutput: printed), "/opt/bin:/usr/bin")
        XCTAssertNil(CodexPluginTargets.getPath(fromShellOutput: "/opt/bin:/usr/bin\n"), "no marker, no path")
    }

    func testAFishPathJoinedWithSpacesIsSplitOnSpaces() {
        let printed = "\n__HATS_PATH__/Users/someone/.local/bin /opt/homebrew/bin /usr/bin"

        XCTAssertEqual(
            CodexPluginTargets.getPath(fromShellOutput: printed),
            "/Users/someone/.local/bin:/opt/homebrew/bin:/usr/bin"
        )
        XCTAssertEqual(CodexPluginTargets.printPath, "printf '\\n__HATS_PATH__%s' \"$PATH\"")
    }

    func testTheCodexFolderGoesFirstWhenThePathLacksIt() {
        let fake = FakePluginWorld()

        let target = CodexPluginTargets.createTarget(cli: "/a/codex", path: "/usr/bin:/bin", world: fake.world())

        XCTAssertEqual(target.environment["PATH"], "/a:/usr/bin:/bin")
    }

    func testNoCodexAnywhereIsNoTarget() {
        let fake = FakePluginWorld()
        fake.answers[shellKey] = FakePluginWorld.printed("\n__HATS_PATH__/usr/bin:/bin")

        XCTAssertNil(CodexPluginTargets.find(in: fake.world()))
        XCTAssertEqual(CodexPluginSteps.findFace(in: fake.world()), .noCodex)
        XCTAssertEqual(fake.changingRuns, [])
    }

    func testAFailingShellIsNoTarget() {
        let fake = FakePluginWorld()
        fake.answers[shellKey] = PluginCommandOutcome(end: .timedOut)

        XCTAssertNil(CodexPluginTargets.find(in: fake.world()))
    }

    func testTheCodexHomeFollowsTheStateFolderOverride() {
        let fake = FakePluginWorld()
        fake.executables = ["/opt/homebrew/bin/codex"]
        fake.environment[StateDirectory.overrideName] = "/tmp/state"

        XCTAssertEqual(CodexPluginTargets.find(in: fake.world())?.environment["CODEX_HOME"], "/tmp/state/codex")

        fake.environment["CODEX_HOME"] = "/elsewhere/codex"
        XCTAssertEqual(CodexPluginTargets.find(in: fake.world())?.codexHome, "/elsewhere/codex")
    }

    func testAfterQuitNoCodexCommandStarts() {
        let fake = FakePluginWorld.withCodex()
        let center = NotificationCenter()
        let work = SessionHandoffWork(world: fake.world(), center: center)

        center.post(name: NSApplication.willTerminateNotification, object: nil)
        let face = CodexPluginSteps.findFace(in: work.world)

        XCTAssertEqual(fake.runs, [], "after Quit not one codex command reaches the system")
        guard case .unknown(let reason) = face else { return XCTFail("\(face)") }
        XCTAssertTrue(reason.contains("Hats is quitting"))
    }
}
