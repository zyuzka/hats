import XCTest
@testable import Hats

final class ShellProfileTests: XCTestCase {
    private let home = "/Users/x"

    private func target(
        _ shell: String?,
        zdotdir: String? = nil,
        existing: Set<String> = []
    ) -> ShellTarget? {
        ShellProfile.target(
            shell: shell,
            home: home,
            zdotdir: zdotdir,
            exists: { existing.contains($0) }
        )
    }

    func testEachKnownShellGetsItsOwnFileAndSyntax() {
        let cases: [(shell: String, path: String, dialect: ShellDialect)] = [
            ("/bin/zsh", "/Users/x/.zshrc", .posix),
            ("/opt/homebrew/bin/fish", "/Users/x/.config/fish/config.fish", .fish),
            ("/bin/sh", "/Users/x/.profile", .posix),
            ("/bin/dash", "/Users/x/.profile", .posix),
            ("/bin/ksh", "/Users/x/.profile", .posix),
            ("/bin/tcsh", "/Users/x/.tcshrc", .csh),
            ("/bin/csh", "/Users/x/.cshrc", .csh),
        ]
        for testCase in cases {
            let got = target(testCase.shell)
            XCTAssertEqual(got?.path, testCase.path, testCase.shell)
            XCTAssertEqual(got?.dialect, testCase.dialect, testCase.shell)
        }
    }

    func testZshFollowsZdotdirWhenItIsSet() {
        XCTAssertEqual(target("/bin/zsh", zdotdir: "/Users/x/.config/zsh")?.path,
                       "/Users/x/.config/zsh/.zshrc")
        XCTAssertEqual(target("/bin/zsh", zdotdir: "")?.path, "/Users/x/.zshrc")
    }

    func testBashFollowsItsOwnPrecedenceAndNeverShadowsAnExistingProfile() {
        let cases: [(existing: Set<String>, path: String, why: String)] = [
            (["/Users/x/.bash_profile"], "/Users/x/.bash_profile", "the first it reads"),
            (["/Users/x/.bash_login"], "/Users/x/.bash_login", "the second it reads"),
            (["/Users/x/.profile"], "/Users/x/.profile",
             "an existing .profile must not be shadowed by a new .bash_profile"),
            (["/Users/x/.profile", "/Users/x/.bash_profile"], "/Users/x/.bash_profile",
             "with both, bash reads .bash_profile, so that is ours too"),
            (["/Users/x/.bashrc"], "/Users/x/.bash_profile",
             "a login bash never reads .bashrc; an export in .bash_profile reaches the shells that do"),
            ([], "/Users/x/.bash_profile", "with none, create the one bash reads first"),
        ]
        for testCase in cases {
            XCTAssertEqual(target("/bin/bash", existing: testCase.existing)?.path,
                           testCase.path, testCase.why)
        }
    }

    func testAnUnknownOrMissingShellGetsNoTargetRatherThanAGuess() {
        XCTAssertNil(target("/usr/local/bin/nushell"))
        XCTAssertNil(target("/opt/homebrew/bin/elvish"))
        XCTAssertNil(target(nil))
        XCTAssertNil(target(""))
    }

    func testTheLoginShellIsReadFromThePasswordDatabaseOnThisMachine() throws {
        let database = getpwuid(getuid())?.pointee.pw_shell.map { String(cString: $0) } ?? ""
        let environment = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        try XCTSkipIf(database.isEmpty && environment.isEmpty,
                      "this machine offers no login shell to read")

        XCTAssertEqual(ShellProfile.loginShell(), database.isEmpty ? environment : database,
                       "the password database first, SHELL only when it has nothing")
    }

    func testEachDialectWritesItsOwnExportAndReadsItBack() {
        let cases: [(dialect: ShellDialect, line: String)] = [
            (.posix, "export ANTHROPIC_BASE_URL=http://127.0.0.1:8787"),
            (.fish, "set -gx ANTHROPIC_BASE_URL http://127.0.0.1:8787"),
            (.csh, "setenv ANTHROPIC_BASE_URL http://127.0.0.1:8787"),
        ]
        for testCase in cases {
            let written = testCase.dialect.exportLine(
                ShellEnvironment.baseURLName,
                "http://127.0.0.1:8787"
            )
            XCTAssertEqual(written, testCase.line)
            XCTAssertEqual(
                testCase.dialect.value(in: written, name: ShellEnvironment.baseURLName),
                "http://127.0.0.1:8787"
            )
        }
    }

    func testATrailingCommentIsNotPartOfTheValueInAnyDialect() {
        let url = "http://127.0.0.1:8787"
        let lines: [(dialect: ShellDialect, line: String)] = [
            (.posix, "export ANTHROPIC_BASE_URL=\(url) # hats"),
            (.posix, "export ANTHROPIC_BASE_URL=\"\(url)\" # hats"),
            (.posix, "ANTHROPIC_BASE_URL='\(url)'  # quoted, two spaces"),
            (.fish, "set -gx ANTHROPIC_BASE_URL \(url) # hats"),
            (.csh, "setenv ANTHROPIC_BASE_URL \(url) # hats"),
        ]
        for testCase in lines {
            XCTAssertEqual(
                testCase.dialect.value(in: testCase.line, name: ShellEnvironment.baseURLName),
                url,
                "the shell reads the value up to the first blank, and so must we: "
                    + testCase.line
            )
        }
        XCTAssertNil(ShellDialect.posix.value(in: "export ANTHROPIC_BASE_URL= # nothing",
                                              name: ShellEnvironment.baseURLName),
                     "a comment is not a value either")
    }

    func testAPosixLineCarryingSeveralAssignmentsIsSearchedForOurs() {
        let name = ShellEnvironment.baseURLName
        let url = "http://127.0.0.1:8787"
        XCTAssertEqual(ShellDialect.posix.value(in: "export PATH=/usr/bin ANTHROPIC_BASE_URL=\(url)", name: name),
                       url, "the shell exports both; ours is not always the first")
        XCTAssertEqual(ShellDialect.posix.value(in: "PATH=/usr/bin ANTHROPIC_BASE_URL=\(url) LANG=C", name: name),
                       url, "and it need not be the last either")
        XCTAssertEqual(ShellDialect.posix.value(in: "export ANTHROPIC_BASE_URL=\(url) LANG=C", name: name), url)
        XCTAssertNil(ShellDialect.posix.value(in: "export PATH=/usr/bin LANG=C", name: name),
                     "a line of assignments that are not ours sets nothing of ours")
        XCTAssertNil(ShellDialect.posix.value(in: "export PATH=/usr/bin # ANTHROPIC_BASE_URL=\(url)", name: name),
                     "past a comment token the line is a comment, assignments and all")
        XCTAssertNil(ShellDialect.posix.value(in: "alias ll=\"ls -la\" ANTHROPIC_BASE_URL=\(url)", name: name),
                     "a word that is not an assignment ends the run; this line runs a command")
    }

    func testAHashInsideAPosixAssignmentIsPartOfTheValueButAHashTokenIsAComment() {
        let name = ShellEnvironment.baseURLName
        XCTAssertEqual(ShellDialect.posix.value(in: "export ANTHROPIC_BASE_URL=#disabled", name: name),
                       "#disabled", "the shell assigns #disabled; a # inside a word is not a comment")
        XCTAssertEqual(ShellDialect.posix.value(in: "ANTHROPIC_BASE_URL=\"#x\" # note", name: name), "#x")
        XCTAssertNil(ShellDialect.fish.value(in: "set -gx ANTHROPIC_BASE_URL #disabled", name: name),
                     "in fish the value is its own token, and a token starting with # is a comment")
        XCTAssertNil(ShellDialect.csh.value(in: "setenv ANTHROPIC_BASE_URL #disabled", name: name),
                     "the same in csh")
    }

    func testAControlOperatorEndsAnUnquotedValueTheWayTheShellEndsIt() {
        let url = "http://127.0.0.1:8787"
        let lines: [(dialect: ShellDialect, line: String)] = [
            (.posix, "export ANTHROPIC_BASE_URL=\(url);"),
            (.posix, "export ANTHROPIC_BASE_URL=\(url); echo hi"),
            (.posix, "ANTHROPIC_BASE_URL=\(url)&"),
            (.posix, "export ANTHROPIC_BASE_URL=\(url)|tee log"),
            (.posix, "export ANTHROPIC_BASE_URL=\(url)>out"),
            (.posix, "export ANTHROPIC_BASE_URL=\(url)<in"),
            (.posix, "export ANTHROPIC_BASE_URL=\(url))"),
            (.fish, "set -gx ANTHROPIC_BASE_URL \(url); echo hi"),
            (.csh, "setenv ANTHROPIC_BASE_URL \(url); echo hi"),
        ]
        for testCase in lines {
            XCTAssertEqual(
                testCase.dialect.value(in: testCase.line, name: ShellEnvironment.baseURLName),
                url,
                "a control operator ends the word without any blank before it: " + testCase.line
            )
        }
    }

    func testQuotesKeepAControlOperatorInsideTheValue() {
        let name = ShellEnvironment.baseURLName
        XCTAssertEqual(ShellDialect.posix.value(in: "export ANTHROPIC_BASE_URL=\"http://x;y\"", name: name),
                       "http://x;y", "inside quotes a control operator is an ordinary character")
        XCTAssertEqual(ShellDialect.posix.value(in: "ANTHROPIC_BASE_URL='http://x&y'", name: name),
                       "http://x&y")
        XCTAssertEqual(ShellDialect.posix.value(in: "export ANTHROPIC_BASE_URL=\"http://x\";echo hi", name: name),
                       "http://x", "the closing quote ends the value, the operator after it is another command")
    }

    func testAnyRunOfWhitespaceSeparatesTheWordsOfAnExportLine() {
        let url = "http://127.0.0.1:8787"
        let lines: [(dialect: ShellDialect, line: String)] = [
            (.posix, "export\tANTHROPIC_BASE_URL=\(url)"),
            (.posix, "export   ANTHROPIC_BASE_URL=\(url)"),
            (.posix, "\t  export ANTHROPIC_BASE_URL=\(url)"),
            (.posix, "   ANTHROPIC_BASE_URL=\(url)"),
            (.fish, "set  -gx\tANTHROPIC_BASE_URL   \(url)"),
            (.fish, "set -x ANTHROPIC_BASE_URL \(url)"),
            (.csh, "setenv\tANTHROPIC_BASE_URL\t\(url)"),
        ]
        for testCase in lines {
            XCTAssertEqual(testCase.dialect.value(in: testCase.line, name: ShellEnvironment.baseURLName), url,
                           "the shell does not count spaces, and neither may we: " + testCase.line.debugDescription)
        }
        XCTAssertNil(ShellDialect.posix.value(in: "exportANTHROPIC_BASE_URL=\(url)",
                                              name: ShellEnvironment.baseURLName),
                     "no whitespace at all is a different word, not an export")
        XCTAssertNil(ShellDialect.posix.value(in: "export ANTHROPIC_BASE_URL_OLD=\(url)",
                                              name: ShellEnvironment.baseURLName),
                     "a longer name that starts with ours is not ours")
    }

    func testADialectDoesNotReadAnotherDialectsLine() {
        let fishLine = "set -gx ANTHROPIC_BASE_URL http://127.0.0.1:8787"
        XCTAssertNil(ShellDialect.posix.value(in: fishLine,
                                              name: ShellEnvironment.baseURLName),
                     "posix must not mistake fish syntax for its own")
        let posixLine = "export ANTHROPIC_BASE_URL=http://127.0.0.1:8787"
        XCTAssertNil(ShellDialect.fish.value(in: posixLine,
                                             name: ShellEnvironment.baseURLName))
        XCTAssertNil(ShellDialect.csh.value(in: posixLine,
                                            name: ShellEnvironment.baseURLName))
    }

    func testFishGetsAFishBlockAndFishIsHowItIsRead() {
        let url = "http://127.0.0.1:8787"
        let block = ShellEnvironment.block(baseURL: url, dialect: .fish)
        XCTAssertTrue(block.contains("set -gx ANTHROPIC_BASE_URL \(url)"))
        XCTAssertFalse(block.contains("export "))
        XCTAssertEqual(
            ShellEnvironment.verdict(profile: block, baseURL: url, dialect: .fish, serving: true),
            .ours
        )
    }

    func testAForeignValueIsRecognisedInEachDialect() {
        let cases: [(ShellDialect, String)] = [
            (.posix, "export ANTHROPIC_BASE_URL=https://proxy.internal\n"),
            (.fish, "set -gx ANTHROPIC_BASE_URL https://proxy.internal\n"),
            (.csh, "setenv ANTHROPIC_BASE_URL https://proxy.internal\n"),
        ]
        for (dialect, profile) in cases {
            XCTAssertEqual(
                ShellEnvironment.verdict(
                    profile: profile,
                    baseURL: "http://127.0.0.1:8787",
                    dialect: dialect,
                    serving: true
                ),
                .foreign(value: "https://proxy.internal")
            )
        }
    }

    func testAnUnreadableProfileIsNotTreatedAsAnEmptyOne() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let missing = directory.appendingPathComponent(".zshrc")
        XCTAssertEqual(GatewayEnvironment.readable(missing), "",
                       "a profile that does not exist yet reads as empty")

        let unreadable = directory.appendingPathComponent(".unreadable")
        try Data([0xff, 0xfe, 0xff]).write(to: unreadable)
        XCTAssertNil(GatewayEnvironment.readable(unreadable),
                     "a file that exists but cannot be decoded must not read as empty — "
                     + "writing over it would take the user's profile with no backup")
    }

    func testTheBackupIsTheFileBeforeTheFirstWriteAndOnlyWhenThereWasAFile() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = directory.appendingPathComponent(".zshrc")
        let backup = directory.appendingPathComponent(".zshrc.bak-hats")

        XCTAssertTrue(GatewayEnvironment.hasWritten("first\n", to: profile, previous: "", existed: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path),
                       "a profile that did not exist leaves nothing to back up")

        XCTAssertTrue(GatewayEnvironment.hasWritten("second\n", to: profile, previous: "first\n", existed: true))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "first\n")

        XCTAssertTrue(GatewayEnvironment.hasWritten("third\n", to: profile, previous: "second\n", existed: true))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "first\n",
                       "the backup is the file before the app's first write, not before its latest")
        XCTAssertEqual(try String(contentsOf: profile, encoding: .utf8), "third\n")
    }

    func testAnEmptyProfileThatExistsIsBackedUpAsEmpty() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = directory.appendingPathComponent(".profile")
        try Data().write(to: profile)

        XCTAssertTrue(GatewayEnvironment.hasWritten("block\n", to: profile, previous: "", existed: true))
        XCTAssertEqual(try String(contentsOf: profile.appendingPathExtension("bak-hats"), encoding: .utf8), "",
                       "an empty file that existed is a file, and it gets its backup like any other")
    }

    func testAnUnknownShellIsReportedRatherThanIgnored() {
        let report = GatewayEnvironmentReport(verdict: nil, profilePath: nil, wrote: false)
        XCTAssertTrue(report.isWarning)
        XCTAssertEqual(report.menuLine,
                       "unknown login shell — set the three gateway variables yourself")
    }
}
