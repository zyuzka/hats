import XCTest
@testable import Hats

final class SessionHandoffTargetTests: XCTestCase {
    private static let homebrewCLI = "/opt/homebrew/bin/claude"

    func testTheSessionVariablesOfAParentClaudeAreDroppedFromEveryCommand() throws {
        let fake = FakePluginWorld()
        fake.environment["CLAUDECODE"] = "1"
        fake.environment["CLAUDE_CODE_CHILD_SESSION"] = "1"
        fake.environment["CLAUDE_CODE_ENTRYPOINT"] = "cli"
        fake.environment["CLAUDE_CODE_EXECPATH"] = "/somewhere/claude"

        let target = try SessionHandoffTargets.find(in: fake.world()).get()

        for name in SessionHandoffTargets.sessionVariables {
            XCTAssertNil(target.environment[name], "\(name) makes claude plugin answer as a model, not as a command")
        }
        XCTAssertTrue(fake.runs.allSatisfy { $0.environment["CLAUDECODE"] == nil })
    }

    func testTheLiveSessionDecidesTheFolderTheVariablesAndThePath() throws {
        let fake = FakePluginWorld()
        let folder = "/Users/someone/.claude-work"
        fake.directories = [folder]
        fake.environment["CLAUDE_CONFIG_DIR"] = "/Users/someone/.claude-other"
        fake.sessions = [
            LiveCLISession(
                pid: 4242,
                executable: FakePluginWorld.cli,
                environment: [
                    "CLAUDE_CONFIG_DIR": folder,
                    "PATH": "/opt/homebrew/bin:/usr/bin",
                ]
            ),
        ]

        let target = try SessionHandoffTargets.find(in: fake.world()).get()

        XCTAssertEqual(target.configFolder, folder)
        XCTAssertEqual(target.environment["CLAUDE_CONFIG_DIR"], folder)
        XCTAssertEqual(target.environment["PATH"], "/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(target.sessionPath, "/opt/homebrew/bin:/usr/bin")
    }

    func testAnUnsetConfigFolderStaysUnsetInTheCommands() throws {
        let fake = FakePluginWorld()

        let target = try SessionHandoffTargets.find(in: fake.world()).get()

        XCTAssertEqual(target.configFolder, FakePluginWorld.configFolder)
        XCTAssertNil(target.environment["CLAUDE_CONFIG_DIR"],
                     "setting it to ~/.claude would move claude's .claude.json and its keychain entry")
    }

    func testTheClaudeOfTheLiveSessionWinsOverANewerOneOnDisk() throws {
        let fake = FakePluginWorld()
        fake.installed = [Self.homebrewCLI]
        fake.answers[FakePluginWorld.key(Self.homebrewCLI, ["--version"])] = FakePluginWorld.printed("2.1.400 (Claude Code)\n")
        fake.answer(FakePluginWorld.claude(["--version"]), PluginCLISamples.version322)
        fake.sessions = [
            LiveCLISession(pid: 4242, executable: FakePluginWorld.cli, environment: [:]),
        ]

        let target = try SessionHandoffTargets.find(in: fake.world()).get()

        XCTAssertEqual(target.cli, FakePluginWorld.cli)
    }

    func testWithoutSessionsTheNewestClaudeOnDiskIsChosen() throws {
        let fake = FakePluginWorld()
        fake.installed = [Self.homebrewCLI, FakePluginWorld.cli]
        fake.answer(FakePluginWorld.key(Self.homebrewCLI, ["--version"]), PluginCLISamples.version153)

        let target = try SessionHandoffTargets.find(in: fake.world()).get()

        XCTAssertEqual(target.cli, FakePluginWorld.cli, "2.1.322 is newer than 2.1.153, whichever comes first")
    }

    func testAClaudeThatDoesNotSayItsVersionIsSkipped() throws {
        let fake = FakePluginWorld()
        fake.installed = [Self.homebrewCLI, FakePluginWorld.cli]
        fake.answers[FakePluginWorld.key(Self.homebrewCLI, ["--version"])] = PluginCommandOutcome(end: .timedOut)

        let target = try SessionHandoffTargets.find(in: fake.world()).get()

        XCTAssertEqual(target.cli, FakePluginWorld.cli)
    }

    func testWhenNoClaudeOfASessionAnswersTheInstalledOnesAreTried() throws {
        let fake = FakePluginWorld()
        fake.sessions = [
            LiveCLISession(pid: 4242, executable: "/Users/someone/.local/share/claude/versions/2.1.300", environment: [:]),
        ]

        let target = try SessionHandoffTargets.find(in: fake.world()).get()

        XCTAssertEqual(target.cli, FakePluginWorld.cli)
        XCTAssertEqual(fake.runs.first?.executable, "/Users/someone/.local/share/claude/versions/2.1.300",
                       "the session's own claude is asked first")
    }

    func testAClaudeNotFromASessionHasItsOwnFolderFirstOnThePath() throws {
        let fake = FakePluginWorld()
        fake.installed = [Self.homebrewCLI]
        fake.answer(FakePluginWorld.key(Self.homebrewCLI, ["--version"]), PluginCLISamples.version322)
        let wanted = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        let target = try SessionHandoffTargets.find(in: fake.world()).get()

        XCTAssertEqual(target.environment["PATH"], wanted,
                       "an npm claude starts with #!/usr/bin/env node, and node sits beside it, not on Hats' PATH")
        XCTAssertEqual(fake.runs.first?.environment["PATH"], wanted, "the --version probe has it too")
        XCTAssertNil(target.sessionPath, "python3 is then looked for through the login shell")
    }

    func testOneFolderWrittenTwoWaysIsNotNamedTwice() {
        let fake = FakePluginWorld()
        fake.sessions = [
            LiveCLISession(pid: 1, executable: FakePluginWorld.cli, environment: ["CLAUDE_CONFIG_DIR": "/Users/someone/.cw"]),
            LiveCLISession(pid: 2, executable: FakePluginWorld.cli, environment: ["CLAUDE_CONFIG_DIR": "/Users/someone/.cw/"]),
        ]

        let found = SessionHandoffTargets.find(in: fake.world())

        XCTAssertEqual(found, .failure(.sessionsDisagreeOnVariables(["CLAUDE_CONFIG_DIR"])),
                       "the folder is one, but its spelling decides claude's keychain entry")
    }

    func testOneFolderWithAnotherVariableNamesThatVariable() {
        let fake = FakePluginWorld()
        fake.sessions = [
            LiveCLISession(pid: 1, executable: FakePluginWorld.cli, environment: [:]),
            LiveCLISession(pid: 2, executable: FakePluginWorld.cli, environment: ["CLAUDE_CODE_CUSTOM_OAUTH_URL": "https://a"]),
            LiveCLISession(pid: 3, executable: FakePluginWorld.cli, environment: ["CLAUDE_CONFIG_DIR": "/Users/someone/.claude"]),
        ]

        let found = SessionHandoffTargets.find(in: fake.world())

        XCTAssertEqual(found, .failure(.sessionsDisagreeOnVariables([
            "CLAUDE_CODE_CUSTOM_OAUTH_URL",
            "CLAUDE_CONFIG_DIR",
        ])))
        XCTAssertTrue(SessionHandoffCopy.getText(.sessionsDisagreeOnVariables(["CLAUDE_CODE_CUSTOM_OAUTH_URL"]))
            .contains("CLAUDE_CODE_CUSTOM_OAUTH_URL"))
    }

    func testTwoFoldersAreNamedOnceEach() {
        let fake = FakePluginWorld()
        fake.sessions = [
            LiveCLISession(pid: 1, executable: FakePluginWorld.cli, environment: [:]),
            LiveCLISession(pid: 2, executable: FakePluginWorld.cli, environment: ["CLAUDE_CODE_CUSTOM_OAUTH_URL": "https://a"]),
            LiveCLISession(pid: 3, executable: FakePluginWorld.cli, environment: ["CLAUDE_CONFIG_DIR": "/Users/someone/.cw"]),
        ]

        let found = SessionHandoffTargets.find(in: fake.world())

        XCTAssertEqual(found, .failure(.sessionsDisagree([
            "/Users/someone/.claude",
            "/Users/someone/.cw",
        ])))
    }

    func testVersionsAreReadFromTheFirstWord() {
        XCTAssertEqual(SessionHandoffTargets.getVersion("2.1.322 (Claude Code)\n"), [2, 1, 322])
        XCTAssertNil(SessionHandoffTargets.getVersion("Claude Code\n"))
        XCTAssertNil(SessionHandoffTargets.getVersion(""))
    }

    func testInstalledCLIsAreFoundOncePerRealFile() {
        let found = InstalledCLIs.find(
            home: "/Users/someone",
            environment: ["PATH": "relative:/opt/homebrew/bin:/usr/bin"],
            isExecutable: { $0 == "/opt/homebrew/bin/claude" || $0 == "/Users/someone/.local/bin/claude" }
        )

        XCTAssertEqual(found, [
            "/opt/homebrew/bin/claude",
            "/Users/someone/.local/bin/claude",
        ])
    }

    func testLiveSessionsKeepOnlyTrustedClaudesWithTheirPathAndConfiguration() {
        let sessions = [
            Session(pid: 1, elapsed: "1", isInteractive: true),
            Session(pid: 2, elapsed: "1", isInteractive: true),
            Session(pid: 3, elapsed: "1", isInteractive: false),
        ]
        var keysAsked: [Set<String>?] = []

        let found = LiveCLISessions.find(
            sessions: sessions,
            isTrusted: { $0 != 2 },
            reading: { pid, keys in
                keysAsked.append(keys)
                return pid == 3 ? .processGone : .read(["PATH": "/usr/bin", "CLAUDE_CONFIG_DIR": "/c"])
            },
            executable: { "/bin/claude-\($0)" }
        )

        XCTAssertEqual(found, [
            LiveCLISession(
                pid: 1,
                executable: "/bin/claude-1",
                environment: [
                    "PATH": "/usr/bin",
                    "CLAUDE_CONFIG_DIR": "/c",
                ]
            ),
        ])
        XCTAssertEqual(keysAsked.first ?? nil, CLIState.configKeys.union(["PATH"]))
    }

    func testAnUnreadableSessionMakesTheWholeListUnreadable() {
        let found = LiveCLISessions.find(
            sessions: [Session(pid: 1, elapsed: "1", isInteractive: true)],
            isTrusted: { _ in true },
            reading: { _, _ in .unreadable },
            executable: { _ in nil }
        )

        XCTAssertNil(found)
    }

    func testAnUnknownTrustMakesTheWholeListUnreadable() {
        let found = LiveCLISessions.find(
            sessions: [Session(pid: 1, elapsed: "1", isInteractive: true)],
            isTrusted: { _ in nil },
            reading: { _, _ in .read([:]) },
            executable: { _ in nil }
        )

        XCTAssertNil(found)
    }

    func testTheExecutableOfAProcessIsFoundByItsPid() throws {
        let own = try XCTUnwrap(LiveCLISessions.getExecutable(of: getpid()))

        XCTAssertTrue(PluginFiles.isExecutableFile(own), own)
        XCTAssertNil(LiveCLISessions.getExecutable(of: -1))
    }
}
