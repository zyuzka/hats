import XCTest
@testable import Hats

final class ShellEnvironmentTests: XCTestCase {
    private let url = "http://127.0.0.1:8787"

    func testAnEmptyProfileHasNothingSetAndGetsTheBlock() {
        XCTAssertEqual(ShellEnvironment.verdict(profile: "", baseURL: url, dialect: .posix, serving: true), .absent)
        let written = ShellEnvironment.applied(to: "", baseURL: url, dialect: .posix, serving: true)
        XCTAssertNotNil(written)
        XCTAssertTrue(written!.contains("export ANTHROPIC_BASE_URL=\(url)"))
        XCTAssertTrue(written!.hasPrefix(ShellEnvironment.openMarker),
                      "a new file starts with the block, not with a blank line")
        XCTAssertTrue(written!.hasSuffix(ShellEnvironment.closeMarker + "\n"))
    }

    func testTheBlockIsSetOffByExactlyOneBlankLineWhateverTheProfileEndsWith() {
        let block = ShellEnvironment.block(baseURL: url, dialect: .posix)
        for ending in ["x=1", "x=1\n", "x=1\n\n"] {
            XCTAssertEqual(ShellEnvironment.applied(to: ending, baseURL: url, dialect: .posix, serving: true),
                           "x=1\n\n" + block + "\n",
                           "one blank line between the profile and the block, given " + ending.debugDescription)
        }
    }

    func testAnythingEditedInsideTheMarkersIsRewrittenBecauseTheMarkersClaimIt() {
        let edited = ShellEnvironment.block(baseURL: url, dialect: .posix)
            .replacingOccurrences(of: "export ANTHROPIC_BASE_URL=\(url)",
                                  with: "export ANTHROPIC_BASE_URL=\(url) # the switcher's port")
        let profile = "x=1\n\n" + edited + "\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: profile, baseURL: url, dialect: .posix, serving: true),
                       .oursOutdated(current: url),
                       "ours means byte-identical to what we would write now; anything else between "
                           + "the markers is a block of some older shape that has to be migrated")
        let after = ShellEnvironment.applied(to: profile, baseURL: url, dialect: .posix, serving: true)
        XCTAssertEqual(after, "x=1\n\n" + ShellEnvironment.block(baseURL: url, dialect: .posix) + "\n")
        XCTAssertEqual(after?.contains("the switcher's port"), false,
                       "an edit inside markers marked as ours does not survive; text outside them does")
    }

    func testAnOldUnconditionalBlockIsMigratedEvenThoughItsPortIsUnchanged() {
        let old = [ShellEnvironment.openMarker,
                   "export ANTHROPIC_BASE_URL=\(url)",
                   "export _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1",
                   "export CLAUDE_GATEWAY_ALLOW_LOOPBACK=1",
                   ShellEnvironment.closeMarker].joined(separator: "\n")
        let profile = "x=1\n\n" + old + "\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: profile, baseURL: url, dialect: .posix, serving: true),
                       .oursOutdated(current: url),
                       "comparing the URL alone answered ours here, so no existing user would ever "
                           + "have been migrated to the conditional block")
        let after = ShellEnvironment.applied(to: profile, baseURL: url, dialect: .posix, serving: true)
        XCTAssertEqual(after, "x=1\n\n" + ShellEnvironment.block(baseURL: url, dialect: .posix) + "\n")
        XCTAssertEqual(ShellEnvironment.verdict(profile: after ?? "", baseURL: url, dialect: .posix, serving: true),
                       .ours, "the migration happens once and settles")
        XCTAssertNil(ShellEnvironment.applied(to: after ?? "", baseURL: url, dialect: .posix, serving: true))
    }

    func testTheBlockAsksTheControlPathBeforeItExportsAnything() {
        let closings: [(ShellDialect, String)] = [(.posix, "fi"), (.fish, "end"), (.csh, "endif")]
        for (dialect, closing) in closings {
            let lines = ShellEnvironment.block(baseURL: url, dialect: dialect)
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            XCTAssertEqual(lines.first, ShellEnvironment.openMarker)
            XCTAssertEqual(lines.last, ShellEnvironment.closeMarker)
            XCTAssertTrue(lines[1].hasPrefix("if "), "the exports are guarded, not asserted: \(lines[1])")
            XCTAssertTrue(lines[1].contains(url + GatewayPaths.control),
                          "the probe asks the control path, never the bare port — something else "
                              + "listening there would be handed the bearer token: \(lines[1])")
            XCTAssertTrue(lines[1].contains("/usr/bin/curl "),
                          "an unqualified name is whatever the user's PATH, alias or function "
                              + "resolves it to, and this line runs at every interactive shell start")
            if dialect != .csh {
                XCTAssertTrue(lines[1].contains("/usr/bin/grep -qF -- "),
                              "fixed-string matching, by absolute path: measured on this machine, an "
                                  + "interactive zsh resolves grep to an alias")
            }
            for command in [ShellEnvironment.curlPath, ShellEnvironment.grepPath] {
                XCTAssertTrue(command.hasPrefix("/"), "\(command) has to be absolute")
            }
            XCTAssertEqual(lines[lines.count - 2], closing, "\(dialect) closes its conditional with \(closing)")
            for line in lines[2..<(lines.count - 2)] {
                XCTAssertTrue(line.hasPrefix("    "), "every export sits inside the conditional: \(line)")
            }
        }
    }

    func testTheProbeLineIsNotReadAsAnAssignmentEvenThoughItCarriesTheURL() {
        for dialect in [ShellDialect.posix, .fish, .csh] {
            let probeLine = ShellEnvironment.block(baseURL: url, dialect: dialect)
                .split(separator: "\n").map(String.init)[1]
            XCTAssertNil(dialect.value(in: probeLine, name: ShellEnvironment.baseURLName),
                         "the URL inside the probe is an argument, not a value we set: \(probeLine)")
            XCTAssertFalse(dialect.containsAnAssignment(to: ShellEnvironment.baseURLName, in: probeLine),
                           "reading the probe as somebody's assignment would make the app refuse "
                               + "its own block forever: \(probeLine)")
        }
    }

    func testTheIndentedExportStaysReadableToAnOlderBuild() {
        for dialect in [ShellDialect.posix, .fish, .csh] {
            let block = ShellEnvironment.block(baseURL: url, dialect: dialect)
            let found = block.split(separator: "\n").compactMap {
                dialect.value(in: String($0), name: ShellEnvironment.baseURLName)
            }
            XCTAssertEqual(found, [url],
                           "an older build splits on whitespace, so the indented export is still "
                               + "found and its withdrawal still works: \(dialect)")
            XCTAssertEqual(ShellEnvironment.removed(from: block + "\n"), "",
                           "removal is marker to marker and takes the conditional with it")
        }
    }

    static func onPath(_ name: String) -> [String] {
        var seen = ["/opt/homebrew/bin/", "/usr/local/bin/", "/opt/local/bin/", "/usr/bin/", "/bin/"]
        seen += (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { String($0) + "/" }
        return Array(Set(seen.map { $0 + name }))
    }

    func testEveryDialectsBlockParsesInTheShellItIsWrittenFor() throws {
        let shells: [(ShellDialect, [String], [String])] = [
            (.posix, ["/bin/zsh", "/bin/bash", "/bin/sh"], ["-n"]),
            (.fish, Self.onPath("fish"), ["--no-execute"]),
            (.csh, ["/bin/tcsh", "/bin/csh"], ["-n"]),
        ]
        var checked: [String] = []
        for (dialect, candidates, arguments) in shells {
            let file = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("hats-block-\(UUID().uuidString).sh")
            try ShellEnvironment.block(baseURL: url, dialect: dialect).write(
                to: file, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: file) }
            for shell in candidates where FileManager.default.isExecutableFile(atPath: shell) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = arguments + [file.path]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try process.run()
                process.waitUntilExit()
                XCTAssertEqual(process.terminationStatus, 0,
                               "\(shell) refused the \(dialect) block as invalid syntax")
                checked.append(shell)
            }
        }
        XCTAssertFalse(checked.isEmpty, "no shell on this machine could check any block")
        print("syntax-checked by: \(checked.joined(separator: ", "))")
    }

    func testSomebodyElsesValueWrittenWithExtraWhitespaceIsStillTheirs() {
        let profile = "export   ANTHROPIC_BASE_URL=https://proxy.internal\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: profile, baseURL: url, dialect: .posix, serving: true),
                       .foreign(value: "https://proxy.internal"),
                       "missing this would append our block over a value somebody set on purpose")
        XCTAssertNil(ShellEnvironment.applied(to: profile, baseURL: url, dialect: .posix, serving: true))
    }

    func testSomebodyElsesValueIsReportedWithoutItsComment() {
        let profile = "export ANTHROPIC_BASE_URL=https://proxy.internal # corporate\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: profile, baseURL: url, dialect: .posix, serving: true),
                       .foreign(value: "https://proxy.internal"))
    }

    func testAProfileWithOtherLinesKeepsThemAllAndGainsTheBlockAtTheEnd() {
        let before = "export PATH=/usr/bin\nalias ll='ls -la'"
        let after = ShellEnvironment.applied(to: before, baseURL: url, dialect: .posix, serving: true)!
        XCTAssertTrue(after.hasPrefix(before))
        XCTAssertTrue(after.contains("export CLAUDE_GATEWAY_ALLOW_LOOPBACK=1"))
    }

    func testOurOwnBlockIsRecognisedAndNotWrittenTwice() {
        let profile = "x=1\n\n" + ShellEnvironment.block(baseURL: url, dialect: .posix) + "\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: profile, baseURL: url, dialect: .posix, serving: true), .ours)
        XCTAssertNil(ShellEnvironment.applied(to: profile, baseURL: url, dialect: .posix, serving: true))
    }

    func testOurBlockOnADifferentPortIsRewrittenInPlace() {
        let profile = "x=1\n" + ShellEnvironment.block(baseURL: "http://127.0.0.1:9999", dialect: .posix) + "\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: profile, baseURL: url, dialect: .posix, serving: true),
                       .oursOutdated(current: "http://127.0.0.1:9999"))
        let after = ShellEnvironment.applied(to: profile, baseURL: url, dialect: .posix, serving: true)!
        XCTAssertTrue(after.contains("export ANTHROPIC_BASE_URL=\(url)"))
        XCTAssertFalse(after.contains("9999"))
        XCTAssertEqual(after.components(separatedBy: ShellEnvironment.openMarker).count - 1, 1)
    }

    func testSomebodyElsesValueIsLeftAloneAndReported() {
        let profile = "export ANTHROPIC_BASE_URL=https://proxy.internal\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: profile, baseURL: url, dialect: .posix, serving: true),
                       .foreign(value: "https://proxy.internal"))
        XCTAssertNil(ShellEnvironment.applied(to: profile, baseURL: url, dialect: .posix, serving: true))
    }

    func testAValueWithoutExportCountsAsSetToo() {
        let profile = "ANTHROPIC_BASE_URL=\"https://proxy.internal\"\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: profile, baseURL: url, dialect: .posix, serving: true),
                       .foreign(value: "https://proxy.internal"))
    }

    func testACommentedOutValueIsNotAValue() {
        let profile = "# export ANTHROPIC_BASE_URL=https://old.example\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: profile, baseURL: url, dialect: .posix, serving: true), .absent)
    }

    func testWhileTheGatewayIsNotServingOurBlockIsWithdrawnAndOnlyOurs() {
        let block = ShellEnvironment.block(baseURL: url, dialect: .posix)
        let ours = "x=1\n\n" + block + "\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: ours, baseURL: url, dialect: .posix, serving: false),
                       .withdrawn)
        let after = ShellEnvironment.applied(to: ours, baseURL: url, dialect: .posix, serving: false)
        XCTAssertEqual(after?.contains(ShellEnvironment.openMarker), false,
                       "a port we could not bind belongs to somebody else; sessions must not be sent there")
        XCTAssertEqual(after?.hasPrefix("x=1\n"), true, "the rest of the profile stays")

        let outdated = "x=1\n" + ShellEnvironment.block(baseURL: "http://127.0.0.1:9999", dialect: .posix) + "\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: outdated, baseURL: url, dialect: .posix, serving: false),
                       .withdrawn)
        XCTAssertEqual(ShellEnvironment.applied(to: outdated, baseURL: url, dialect: .posix, serving: false)?
            .contains("9999"), false, "an outdated block of ours goes the same way")

        XCTAssertEqual(ShellEnvironment.verdict(profile: "x=1\n", baseURL: url, dialect: .posix, serving: false),
                       .withdrawn)
        XCTAssertNil(ShellEnvironment.applied(to: "x=1\n", baseURL: url, dialect: .posix, serving: false),
                     "nothing of ours to take out, nothing to write")

        let foreign = "export ANTHROPIC_BASE_URL=https://proxy.internal\n"
        XCTAssertEqual(ShellEnvironment.verdict(profile: foreign, baseURL: url, dialect: .posix, serving: false),
                       .foreign(value: "https://proxy.internal"), "somebody else's value is not ours to withdraw")
        XCTAssertNil(ShellEnvironment.applied(to: foreign, baseURL: url, dialect: .posix, serving: false))
    }

    func testAddingAndRemovingTheBlockRoundTripsToTheProfileAsItWas() {
        let block = ShellEnvironment.block(baseURL: url, dialect: .posix)
        let cases: [(before: String, why: String)] = [
            ("", "a file we created is empty again, not a lone newline"),
            ("x=1\n", "the user's line and its newline, nothing more"),
            ("x=1", "a file without a trailing newline gets one back at most"),
        ]
        for testCase in cases {
            let written = ShellEnvironment.applied(to: testCase.before, baseURL: url, dialect: .posix, serving: true)
            let restored = written.flatMap(ShellEnvironment.removed(from:))
            let expected = testCase.before.isEmpty || testCase.before.hasSuffix("\n")
                ? testCase.before : testCase.before + "\n"
            XCTAssertEqual(restored, expected, testCase.why)
        }

        let blockOnTop = block + "\n\nx=1\n"
        XCTAssertEqual(ShellEnvironment.removed(from: blockOnTop), "x=1\n",
                       "a block removed from the top leaves no blank lines above the user's text")
    }

    func testWithdrawingTheBlockTouchesNothingAwayFromIt() {
        let owned = "\n\nexport A=1\n\n\n\nexport B=2\n"
        let written = ShellEnvironment.applied(to: owned, baseURL: url, dialect: .posix,
                                               serving: true)!
        XCTAssertEqual(ShellEnvironment.removed(from: written), owned,
                       "blank lines the user opened the file with, and a run of them in the middle, "
                           + "are the user's bytes; withdrawing our block is not licence to tidy them")
    }

    func testABlankProfileGetsTheBlockFromItsFirstLine() {
        let block = ShellEnvironment.block(baseURL: url, dialect: .posix)
        for blank in ["\n", "\n\n", "  \n"] {
            XCTAssertEqual(ShellEnvironment.applied(to: blank, baseURL: url, dialect: .posix, serving: true),
                           block + "\n",
                           "whitespace is not content; the block starts at the top, given " + blank.debugDescription)
        }
    }

    func testRemovingTheBlockLeavesTheRestOfTheProfileIntact() {
        let profile = ShellEnvironment.applied(to: "export PATH=/usr/bin\n", baseURL: url, dialect: .posix, serving: true)!
        let cleaned = ShellEnvironment.removed(from: profile)!
        XCTAssertTrue(cleaned.contains("export PATH=/usr/bin"))
        XCTAssertFalse(cleaned.contains("ANTHROPIC_BASE_URL"))
        XCTAssertNil(ShellEnvironment.removed(from: cleaned))
    }

    func testTheReportSpeaksPlainlyAboutEachOutcome() {
        let foreign = GatewayEnvironmentReport(
            verdict: .foreign(value: "https://proxy.internal"),
            profilePath: "/x/.zshrc", wrote: false)
        XCTAssertTrue(foreign.isWarning)
        XCTAssertEqual(foreign.menuLine,
                       "ANTHROPIC_BASE_URL is already set to https://proxy.internal — left alone")

        let written = GatewayEnvironmentReport(verdict: .absent, profilePath: "/x/.zshrc",
                                               wrote: true)
        XCTAssertFalse(written.isWarning)
        XCTAssertEqual(written.menuLine,
                       "shells opened from now on send their sessions through the gateway")

        let failed = GatewayEnvironmentReport(verdict: .absent, profilePath: "/x/.zshrc",
                                              wrote: false)
        XCTAssertTrue(failed.isWarning)

        let settled = GatewayEnvironmentReport(verdict: .ours, profilePath: "/x/.zshrc",
                                               wrote: false)
        XCTAssertFalse(settled.isWarning)
        XCTAssertNil(settled.menuLine)

        let unknownShell = GatewayEnvironmentReport(verdict: nil, profilePath: nil, wrote: false)
        XCTAssertTrue(unknownShell.isWarning)
        XCTAssertTrue(unknownShell.menuLine?.contains("unknown login shell") ?? false)

        let unreadable = GatewayEnvironmentReport(verdict: .unreadable, profilePath: "/x/.zshrc",
                                                  wrote: false)
        XCTAssertTrue(unreadable.isWarning)
        XCTAssertTrue(unreadable.menuLine?.contains("could not be read") ?? false,
                      "a profile that could not be read is not an unknown shell, and the menu "
                      + "must not say it is: \(unreadable.menuLine ?? "nil")")
        XCTAssertFalse(unreadable.menuLine?.contains("unknown login shell") ?? true)

        for wrote in [true, false] {
            let withdrawn = GatewayEnvironmentReport(verdict: .withdrawn, profilePath: "/x/.zshrc",
                                                     wrote: wrote)
            XCTAssertTrue(withdrawn.isWarning)
            XCTAssertTrue(withdrawn.menuLine?.contains("not serving") ?? false,
                          "a withdrawn block is reported as such whether or not a write happened; "
                          + "the generic success line must not claim sessions go through the gateway")
        }

        let rewritten = GatewayEnvironmentReport(
            verdict: .oursOutdated(current: "http://127.0.0.1:9999"),
            profilePath: "/x/.zshrc",
            wrote: true
        )
        XCTAssertFalse(rewritten.isWarning)
        XCTAssertEqual(rewritten.menuLine,
                       "the gateway block in the shell profile was updated — terminals already "
                           + "open keep the old variables until they are reopened",
                       "a rewrite succeeded, so it is not a warning — but a user who reads only "
                           + "\"updated\" would assume their open terminals changed too, and they did not")
    }

    private func verdict(_ profile: String, _ dialect: ShellDialect = .posix) -> ShellEnvironment.Verdict {
        ShellEnvironment.verdict(profile: profile, baseURL: "http://127.0.0.1:8787",
                                 dialect: dialect, serving: true)
    }

    private func applied(_ profile: String, _ dialect: ShellDialect = .posix) -> String? {
        ShellEnvironment.applied(to: profile, baseURL: "http://127.0.0.1:8787",
                                 dialect: dialect, serving: true)
    }

    func testALineThisAppCannotReadIsLeftAloneRatherThanWrittenOver() {
        let profile = "source ~/.env; export ANTHROPIC_BASE_URL=http://127.0.0.1:9999\n"
        XCTAssertEqual(verdict(profile), .foreignUnreadable,
                       "a command separator starts a new command and this parser does not model "
                           + "that, so the assignment after it cannot be read — and an unreadable "
                           + "assignment is somebody's value, not an empty slot")
        XCTAssertNil(applied(profile),
                     "appending our block after theirs would win silently, because the shell takes "
                         + "the last assignment")
    }

    func testTheSameRefusalHoldsInFishAndCsh() {
        XCTAssertEqual(verdict("true; set -gx ANTHROPIC_BASE_URL http://x\n", .fish),
                       .foreignUnreadable)
        XCTAssertEqual(verdict("true; setenv ANTHROPIC_BASE_URL http://x\n", .csh),
                       .foreignUnreadable)
    }

    func testAMentionThatAssignsNothingDoesNotBlockTheBlock() {
        XCTAssertEqual(verdict("# ANTHROPIC_BASE_URL=http://x\n"), .absent,
                       "a commented-out line assigns nothing, and refusing on it would wedge the "
                           + "app out of a profile forever")
        XCTAssertEqual(verdict("export PATH=/usr/bin # ANTHROPIC_BASE_URL=http://x\n"), .absent)
        XCTAssertEqual(verdict("export ANTHROPIC_BASE_URL_OLD=http://x\n"), .absent,
                       "a longer name that starts with ours is a different variable")
        XCTAssertNotNil(applied("# ANTHROPIC_BASE_URL=http://x\n"))
    }

    func testNamingTheVariableWithoutAssigningItDoesNotBlockTheBlock() {
        let notAssignments: [(ShellDialect, String)] = [
            (.fish, "set -q ANTHROPIC_BASE_URL\n"),
            (.fish, "if set -q ANTHROPIC_BASE_URL\n"),
            (.fish, "set -e ANTHROPIC_BASE_URL\n"),
            (.fish, "set -l ANTHROPIC_BASE_URL http://x\n"),
            (.fish, "echo ANTHROPIC_BASE_URL\n"),
            (.csh, "unsetenv ANTHROPIC_BASE_URL\n"),
            (.csh, "echo ANTHROPIC_BASE_URL\n"),
        ]
        for (dialect, profile) in notAssignments {
            XCTAssertEqual(verdict(profile, dialect), .absent,
                           "naming a variable is not setting it, and refusing here would keep the "
                               + "app out of the profile for good: " + profile.debugDescription)
        }
    }

    func testAnArgumentThatLooksLikeAnAssignmentIsRefusedToo() {
        XCTAssertEqual(verdict("alias ll=\"ls -la\" ANTHROPIC_BASE_URL=http://x\n"),
                       .foreignUnreadable,
                       "this line assigns nothing — it passes a word to alias — but telling the two "
                           + "apart needs a shell, and the safe reading of an ambiguity is to leave "
                           + "the file alone and say so")
    }

    func testAFailedStartKeepsItsReasonForTheMenu() {
        let failed = GatewayProcess.outcome(started: false, serving: false)
        XCTAssertFalse(failed.isServing)
        XCTAssertEqual(failed, .failed("the port could not be bound"),
                       "a port collision must reach the menu as a reason, not as silence")

        XCTAssertEqual(GatewayProcess.reported(serving: false, last: failed), failed,
                       "the reason a start failed for must survive to the menu")
        XCTAssertEqual(GatewayProcess.reported(serving: true, last: failed), .running,
                       "a serving gateway is running whatever the last failure said")
        XCTAssertEqual(GatewayProcess.reported(serving: false, last: nil), .notRunning,
                       "with no start attempted, the honest answer is not running")
        XCTAssertEqual(GatewayProcess.reported(serving: false, last: .running), .notRunning,
                       "a channel that died without a stop leaves .running behind; reporting it "
                           + "would promise a gateway on the port while nothing listens")
    }

    func testOnlyAServingGatewayCountsAsServing() {
        XCTAssertTrue(GatewayProcess.Status.running.isServing)
        XCTAssertFalse(GatewayProcess.Status.notRunning.isServing)
        XCTAssertFalse(GatewayProcess.Status.failed("x").isServing)
    }

    func testABoundPortThatIsNotServingIsNotRunning() {
        XCTAssertEqual(GatewayProcess.outcome(started: true, serving: true), .running)
        XCTAssertEqual(GatewayProcess.outcome(started: false, serving: false),
                       .failed("the port could not be bound"))
        XCTAssertEqual(GatewayProcess.outcome(started: true, serving: false),
                       .failed("bound but not serving"))
    }
}
