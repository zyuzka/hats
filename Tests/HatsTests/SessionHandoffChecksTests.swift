import XCTest
@testable import Hats

final class SessionHandoffChecksTests: XCTestCase {
    private let shellLookup = FakePluginWorld.key(FakePluginWorld.shell, [
        "-lc",
        "command -v python3",
    ])
    private let xcodeSelect = FakePluginWorld.key(SessionHandoffPython.xcodeSelect, ["-p"])

    private func refusal(_ fake: FakePluginWorld,
                         file: StaticString = #filePath,
                         line: UInt = #line) -> SessionHandoffRefusal? {
        let preparation = SessionHandoffSteps.getPreparation(in: fake.world())
        XCTAssertEqual(fake.changingRuns, [], "a refused install changes nothing", file: file, line: line)
        guard case .refused(let refusal) = preparation else {
            XCTFail("expected a refusal, got \(preparation)", file: file, line: line)
            return nil
        }

        return refusal
    }

    private func liveSession(executable: String? = FakePluginWorld.cli,
                             environment: [String: String] = [:]) -> LiveCLISession {
        LiveCLISession(pid: 4242, executable: executable, environment: environment)
    }

    func testThePlaceholderPythonFoundByTheShellIsRefusedWithoutRunningIt() {
        let fake = FakePluginWorld()
        fake.answers[shellLookup] = FakePluginWorld.printed("/usr/bin/python3\n")
        fake.answers[xcodeSelect] = PluginCommandOutcome(end: .exited(2))

        let refused = refusal(fake)

        XCTAssertEqual(refused, .pythonPlaceholder("/usr/bin/python3"))
        XCTAssertTrue(SessionHandoffCopy.getText(.pythonPlaceholder("/usr/bin/python3")).contains("xcode-select --install"))
        XCTAssertFalse(fake.runs.contains { $0.executable.hasSuffix("python3") }, "/usr/bin/python3 never starts")
        XCTAssertTrue(fake.commands.contains(xcodeSelect))
    }

    func testThePlaceholderReachedThroughALinkOnTheSessionPathIsRefusedToo() {
        let fake = FakePluginWorld()
        fake.sessions = [liveSession(environment: ["PATH": "/usr/local/bin:/usr/bin"])]
        fake.executables = ["/usr/local/bin/python3"]
        fake.sameFiles = ["/usr/local/bin/python3=/usr/bin/python3"]
        fake.answers[xcodeSelect] = PluginCommandOutcome(end: .exited(2))

        let refused = refusal(fake)

        XCTAssertEqual(refused, .pythonPlaceholder("/usr/local/bin/python3"))
        XCTAssertFalse(fake.commands.contains(shellLookup), "with a live session its PATH is searched, not a shell")
        XCTAssertFalse(fake.runs.contains { $0.executable.hasSuffix("python3") })
    }

    func testTheSystemPythonPassesWhenTheCommandLineToolsAreThere() throws {
        let fake = FakePluginWorld()
        fake.answers[shellLookup] = FakePluginWorld.printed("/usr/bin/python3\n")
        fake.answers[xcodeSelect] = FakePluginWorld.printed("/Library/Developer/CommandLineTools\n")

        let preparation = SessionHandoffSteps.getPreparation(in: fake.world())

        guard case .ready(let plan, _) = preparation else { return XCTFail("expected ready, got \(preparation)") }
        XCTAssertEqual(plan.python.path, "/usr/bin/python3")
    }

    func testAnXcodeSelectThatDoesNotFinishIsUncheckedNotAPlaceholder() {
        for (end, reason) in [
            (PluginCommandEnd.timedOut, "timed out"),
            (.signalled(9), "it was stopped by signal 9"),
            (.notStarted("No such file or directory"), "it could not start: No such file or directory"),
        ] {
            let fake = FakePluginWorld()
            fake.answers[shellLookup] = FakePluginWorld.printed("/usr/bin/python3\n")
            fake.answers[xcodeSelect] = PluginCommandOutcome(end: end)

            let preparation = SessionHandoffSteps.getPreparation(in: fake.world())

            XCTAssertEqual(preparation, .refused(.pythonUnchecked("/usr/bin/xcode-select -p: \(reason)")))
        }
    }

    func testAShellStoppedBySignalIsUncheckedNotMissing() {
        let fake = FakePluginWorld()
        fake.answers[shellLookup] = PluginCommandOutcome(end: .signalled(15))

        XCTAssertEqual(refusal(fake), .pythonUnchecked(
            "/bin/zsh did not finish looking for python3: it was stopped by signal 15"
        ))
    }

    func testAHelpThatDoesNotAnswerIsReportedAsSuch() {
        let fake = FakePluginWorld()
        fake.answers[FakePluginWorld.claude(SessionHandoffSteps.helpArguments)] = PluginCommandOutcome(end: .timedOut)

        XCTAssertEqual(refusal(fake), .cliDidNotAnswer(command: "claude plugin install --help", reason: "timed out"))
    }

    func testAPythonElsewhereIsNotCheckedWithXcodeSelect() {
        let fake = FakePluginWorld()

        _ = SessionHandoffSteps.getPreparation(in: fake.world())

        XCTAssertFalse(fake.commands.contains(xcodeSelect))
    }

    func testNoPythonAtAllIsRefused() {
        let fake = FakePluginWorld()
        fake.answers[shellLookup] = FakePluginWorld.printed("", code: 1)

        XCTAssertEqual(refusal(fake), .pythonMissing("a new login shell (/bin/zsh)"))
    }

    func testAShellThatDoesNotAnswerIsRefusedAsUnchecked() {
        let fake = FakePluginWorld()
        fake.answers[shellLookup] = PluginCommandOutcome(end: .timedOut)

        XCTAssertEqual(refusal(fake), .pythonUnchecked("/bin/zsh did not finish looking for python3: timed out"))
        XCTAssertEqual(fake.runs.first { $0.executable == FakePluginWorld.shell }?.seconds, 10)
    }

    func testNoClaudeIsRefused() {
        let fake = FakePluginWorld()
        fake.installed = []

        XCTAssertEqual(refusal(fake), .noCLI)
    }

    func testNoSettingsFolderIsRefused() {
        let fake = FakePluginWorld()
        fake.directories = []

        XCTAssertEqual(refusal(fake), .noConfigFolder(FakePluginWorld.configFolder))
    }

    func testSessionsOnDifferentFoldersAreRefused() {
        let fake = FakePluginWorld()
        fake.sessions = [
            liveSession(environment: [:]),
            liveSession(environment: ["CLAUDE_CONFIG_DIR": "/Users/someone/.claude-work"]),
        ]

        XCTAssertEqual(refusal(fake), .sessionsDisagree([
            "/Users/someone/.claude",
            "/Users/someone/.claude-work",
        ]))
    }

    func testARelativeConfigFolderIsRefused() {
        let fake = FakePluginWorld()
        fake.environment["CLAUDE_CONFIG_DIR"] = "claude-config"

        XCTAssertEqual(refusal(fake), .relativeConfigFolder("claude-config"))
    }

    func testUnreadableSessionsAreRefused() {
        let fake = FakePluginWorld()
        fake.sessions = nil

        XCTAssertEqual(refusal(fake), .sessionsUnreadable)
    }

    func testAnOldClaudeIsRefusedByItsOwnHelp() {
        let fake = FakePluginWorld()
        fake.answer(FakePluginWorld.claude(SessionHandoffSteps.helpArguments), PluginCLISamples.installHelp153)

        XCTAssertEqual(refusal(fake), .cliTooOld(FakePluginWorld.cli))
        XCTAssertTrue(SessionHandoffCopy.getText(.cliTooOld(FakePluginWorld.cli)).contains("too old"))
    }

    func testTheOldHookInSettingsIsShownWithItsFileAndCommand() {
        let fake = FakePluginWorld()
        fake.files[FakePluginWorld.settings] = .read(Data(SessionHandoffInstallTests.settingsWithTheOldHook.utf8))

        let refused = refusal(fake)

        XCTAssertEqual(refused, .oldHook(file: FakePluginWorld.settings, commands: [
            "python3 -I \"$HOME/.claude/hooks/handoff.py\" start",
        ]))
        XCTAssertTrue(SessionHandoffCopy.getText(refused ?? .noCLI).contains("Hats does not edit that file"))
    }

    func testABrokenSettingsFileIsRefused() {
        let fake = FakePluginWorld()
        fake.files[FakePluginWorld.settings] = .read(Data("{ broken\n".utf8))

        XCTAssertEqual(refusal(fake), .brokenSettings(file: FakePluginWorld.settings, reason: "it is not a JSON object"))
    }

    func testAnUnreadableSettingsFileIsRefused() {
        let fake = FakePluginWorld()
        fake.files[FakePluginWorld.settings] = .unreadable("Permission denied")

        XCTAssertEqual(refusal(fake), .brokenSettings(file: FakePluginWorld.settings, reason: "Permission denied"))
    }

    func testNoSettingsFileMeansNoOldHook() {
        let fake = FakePluginWorld()

        let preparation = SessionHandoffSteps.getPreparation(in: fake.world())

        guard case .ready = preparation else { return XCTFail("expected ready, got \(preparation)") }
    }
}
