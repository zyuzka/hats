import CryptoKit
import XCTest
@testable import Hats

final class CLIStateLocationTests: XCTestCase {
    private let home = "/Users/probe"

    private func dir(_ environment: [String: String]) -> URL {
        CLIState.configDir(environment: environment, home: home)
    }

    func testWithoutTheVariableTheConfigurationHomeIsUnderTheUserHome() {
        XCTAssertEqual(dir([:]).path, "/Users/probe/.claude")
    }

    func testAnAbsoluteValueIsTheConfigurationHome() {
        XCTAssertEqual(dir(["CLAUDE_CONFIG_DIR": "/tmp/alt"]).path, "/tmp/alt")
    }

    func testARelativeValueIsIgnoredBecauseTheCLIRefusesOneItself() {
        XCTAssertEqual(dir(["CLAUDE_CONFIG_DIR": "alt/config"]).path, "/Users/probe/.claude")
        XCTAssertEqual(dir(["CLAUDE_CONFIG_DIR": "~/alt"]).path, "/Users/probe/.claude")
    }

    func testABlankValueIsNotAPath() {
        XCTAssertEqual(dir(["CLAUDE_CONFIG_DIR": ""]).path, "/Users/probe/.claude")
        XCTAssertEqual(dir(["CLAUDE_CONFIG_DIR": "   "]).path, "/Users/probe/.claude")
        XCTAssertEqual(dir(["CLAUDE_CONFIG_DIR": "\n"]).path, "/Users/probe/.claude")
    }

    private func picked(_ environment: [String: String], existing: Set<String>) -> CLIStateFile {
        CLIState.stateFile(environment: environment, home: home) { existing.contains($0.path) }
    }

    func testTheOrderIsTheOneTheCLIResolvesIn() {
        let inOrder = CLIState.stateFilesInOrder(environment: [:], home: home).map(\.path)

        XCTAssertEqual(inOrder, ["/Users/probe/.claude/.config.json",
                                 "/Users/probe/.claude.json"],
                       "the CLI takes .config.json inside the configuration home first and the "
                           + "named file beside the home second; we read the file it reads, in its order")
    }

    func testTheConfigJsonWinsWhenBothExist() {
        let both: Set<String> = ["/Users/probe/.claude/.config.json", "/Users/probe/.claude.json"]

        XCTAssertEqual(try picked([:], existing: both),
                       .resolved(URL(fileURLWithPath: "/Users/probe/.claude/.config.json")),
                       "two files are not an ambiguity: the CLI reads the first of them, so we write "
                           + "that one instead of refusing")
    }

    func testTheNamedFileIsReadWhenTheConfigJsonIsAbsent() {
        XCTAssertEqual(try picked([:], existing: ["/Users/probe/.claude.json"]),
                       .resolved(URL(fileURLWithPath: "/Users/probe/.claude.json")))
    }

    func testTheNamedFileSitsBesideTheHomeAndNotInsideTheConfigurationHome() {
        XCTAssertEqual(try picked([:], existing: ["/Users/probe/.claude/.claude.json"]),
                       .missing(CLIState.stateFilesInOrder(environment: [:], home: home)),
                       "with no CLAUDE_CONFIG_DIR the CLI never opens that path, so neither do we — "
                           + "this is the file a machine can be left holding and it is not the account file")
    }

    func testAConfiguredHomeMovesBothSpellingsIntoIt() {
        let inOrder = CLIState
            .stateFilesInOrder(environment: ["CLAUDE_CONFIG_DIR": "/tmp/alt"], home: home)
            .map(\.path)

        XCTAssertEqual(inOrder, ["/tmp/alt/.config.json", "/tmp/alt/.claude.json"])
        XCTAssertFalse(inOrder.contains { $0.hasPrefix(home) })
    }

    func testACustomOAuthURLChangesTheFilenameTheCLIKeeps() {
        let inOrder = CLIState
            .stateFilesInOrder(environment: ["CLAUDE_CODE_CUSTOM_OAUTH_URL": "https://oauth.example"],
                               home: home)
            .map(\.path)

        XCTAssertEqual(inOrder, ["/Users/probe/.claude/.config.json",
                                 "/Users/probe/.claude-custom-oauth.json"],
                       "the CLI suffixes the filename once that variable is set, on any build")
        XCTAssertEqual(CLIState.namedFile(environment: ["CLAUDE_CODE_CUSTOM_OAUTH_URL": "   "]),
                       ".claude.json",
                       "a blank value is not a custom OAuth URL")
    }

    func testASymlinkedLayoutResolvesToTheFileTheCLIOpens() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-alias-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let target = real.appendingPathComponent(".claude.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: base.appendingPathComponent(".claude"), withDestinationURL: real)
        try FileManager.default.createSymbolicLink(
            at: base.appendingPathComponent(".claude.json"), withDestinationURL: target)

        let found = CLIState.stateFile(
            environment: ["CLAUDE_CONFIG_DIR": base.appendingPathComponent(".claude").path],
            home: base.path,
            exists: { FileManager.default.fileExists(atPath: $0.path) }
        )

        XCTAssertEqual(found, .resolved(base.appendingPathComponent(".claude")
                                           .appendingPathComponent(".claude.json")),
                       "the named file inside the configured home is what the CLI opens here, and a "
                           + "symlink to it is the same file")
    }

    private func reading(live: [[String: String]],
                        own: [String: String] = [:],
                        existing: Set<String>) throws -> CLIStateReading {
        try CLIState.configuration(liveConfigurations: live, own: own, home: home)
            .stateFile { existing.contains($0.path) }
    }

    private func refusal(live: [[String: String]], own: [String: String] = [:]) -> CLIStateError? {
        do {
            _ = try CLIState.configuration(liveConfigurations: live, own: own, home: home)
            return nil
        } catch {
            return error as? CLIStateError
        }
    }

    func testTheConfigurationComesFromTheRunningCLIAndNotFromOurOwnEnvironment() throws {
        let answer = try reading(
            live: [[:]],
            own: ["CLAUDE_CONFIG_DIR": "/Users/probe/.claude"],
            existing: ["/Users/probe/.claude.json", "/Users/probe/.claude/.claude.json"]
        )

        XCTAssertEqual(answer.file, .resolved(URL(fileURLWithPath: "/Users/probe/.claude.json")),
                       "the CLI that is running has no configuration home set, so the file it reads "
                           + "is the one beside the home — our own environment is a menu-bar app's "
                           + "environment and says nothing about the shell the sessions came from")
        XCTAssertEqual(answer.source, .liveCLI)
        XCTAssertEqual(answer.journalName, "resolved/fromTheCLI",
                       "the journal has to say where the path came from, or a wrong switch is "
                           + "indistinguishable from a right one")
    }

    func testARunningCLIWithAConfigurationHomeMovesTheFileInsideIt() throws {
        let answer = try reading(
            live: [["CLAUDE_CONFIG_DIR": "/Users/probe/.claude"]],
            own: [:],
            existing: ["/Users/probe/.claude.json", "/Users/probe/.claude/.claude.json"]
        )

        XCTAssertEqual(answer.file,
                       .resolved(URL(fileURLWithPath: "/Users/probe/.claude/.claude.json")),
                       "both files exist and this is the one that CLI opens")
        XCTAssertEqual(answer.source, .liveCLI)
    }

    func testWithNoCLIRunningWeFallBackToOurOwnEnvironmentAndSaySo() throws {
        let answer = try reading(live: [],
                             own: ["CLAUDE_CONFIG_DIR": "/tmp/alt"],
                             existing: ["/tmp/alt/.claude.json"])

        XCTAssertEqual(answer.file, .resolved(URL(fileURLWithPath: "/tmp/alt/.claude.json")))
        XCTAssertEqual(answer.source, .ourOwn)
        XCTAssertEqual(answer.journalName, "resolved/fromOurOwn")
    }

    func testSessionsThatReadDifferentFilesAreARefusalNobodyCanForgetToHandle() {
        let error = refusal(live: [[:], ["CLAUDE_CONFIG_DIR": "/tmp/alt"]])

        guard case .liveCLIsDisagree(let homes)? = error else {
            return XCTFail("expected a disagreement refusal, got \(String(describing: error))")
        }
        XCTAssertEqual(homes, ["/Users/probe/.claude", "/tmp/alt"],
                       "two live sessions reading two files means no single write is right, and the "
                           + "configuration THROWS rather than resolving, so neither the file path "
                           + "nor the credential name can be derived without handling it")
        let message = error?.errorDescription ?? ""
        XCTAssertTrue(message.contains("do not read the same account file"), message)
        XCTAssertTrue(message.contains("/tmp/alt"), message)
    }

    func testTheConfigurationOfAProcessKeepsOnlyTheTwoVariablesThatMoveTheFile() {
        let found = CLIState.configurations(of: [11, 12, 13], trusting: { _ in true }) { pid in
            switch pid {
            case 11:
                return .read(["CLAUDE_CONFIG_DIR": "/tmp/alt", "PATH": "/usr/bin",
                              "HOME": "/Users/x"])
            case 12:
                return .read(["CLAUDE_CONFIG_DIR": "/tmp/alt", "TERM": "xterm"])
            default:
                return .processGone
            }
        }

        XCTAssertEqual(found, [["CLAUDE_CONFIG_DIR": "/tmp/alt"]],
                       "two sessions of one configuration are one configuration, everything but the "
                           + "two variables is dropped, and a session that exited between the sweep "
                           + "and the read is absent rather than a disagreement")
    }

    func testASessionWhoseEnvironmentCannotBeReadRefusesInsteadOfShrinkingTheAnswer() {
        XCTAssertNil(CLIState.configurations(of: [11, 12], trusting: { _ in true }) { pid in
            pid == 11 ? .read(["CLAUDE_CONFIG_DIR": "/tmp/alt"]) : .unreadable
        }, "dropping the unreadable session left one configuration standing, so the guard that "
            + "refuses a switch while live sessions disagree could not fire and the switch was "
            + "written against the only file it could still see")
    }

    func testABlankConfigurationHomeOnALiveSessionIsNotAConfigurationHome() {
        XCTAssertEqual(CLIState.configurations(of: [1], trusting: { _ in true }) { _ in
            .read(["CLAUDE_CONFIG_DIR": "  "])
        }, [[:]])

    }

    func testAProcessThatIsNotTheSignedCLIGetsNoVoteAndIsNotEvenRead() {
        var readAnyway: [Int32] = []
        let found = CLIState.configurations(of: [11], trusting: { _ in false }) { pid in
            readAnyway.append(pid)
            return .read(["CLAUDE_CONFIG_DIR": "/tmp/attacker-owned"])
        }

        XCTAssertEqual(found, [], "any process whose executable is named claude used to be believed "
            + "about which keychain slot and which account file are live, on the strength of a "
            + "filename; an unprivileged process could name them and the switch adopted its answer "
            + "as source == .liveCLI")
        XCTAssertEqual(readAnyway, [], "and its environment is not read at all, so an untrusted "
            + "process cannot reach the refusal path either")
    }

    func testTheSignatureRequirementCompiles() {
        XCTAssertNotNil(TrustedCLI.requirement,
                        "a requirement that does not compile makes isTheRealCLI answer false for "
                            + "every process, which is safe but silent: the app would quietly stop "
                            + "seeing any session's configuration and fall back to its own")
    }

    func testThisProcessIsNotTheRealCLI() {
        XCTAssertEqual(TrustedCLI.isTheRealCLI(pid: getpid()), false,
                       "the requirement has to reject something, or it is not a check — and it must "
                           + "say NO rather than cannot-tell, which is the answer reserved for the "
                           + "requirement itself being unavailable. Measured against the real thing: "
                           + "the four claude sessions running when this was written all passed it, "
                           + "at 2 to 15 ms each")
    }

    func testATrustMechanismThatCannotAnswerRefusesTheSweepRatherThanEmptyingIt() {
        XCTAssertNil(CLIState.configurations(of: [11, 12], trusting: { _ in nil }) { _ in
            .read(["CLAUDE_CONFIG_DIR": "/tmp/alt"])
        }, "a requirement that fails to compile answers false for every pid, which emptied the list "
            + "and read downstream as no session running — so configurationInForce handed the switch "
            + "our own environment exactly when the check meant to protect it was unavailable. That "
            + "is the same laundering this file already closed for a failed process-table read, at a "
            + "second door, and my own test message called it safe but silent instead of fixing it")
    }

    func testAProcessTableThatCouldNotBeReadIsNotAnEmptyListOfSessions() {
        XCTAssertNil(CLIState.swept(nil),
                     "ProcessTable.read answers nil when ps refuses, exits non-zero or is "
                         + "terminated by its five-second budget, and everySessionThatHoldsAPort and "
                         + "everySessionSeenRecently both carry that nil upwards. Turning it into an "
                         + "empty list here switched the disagreement guard off altogether and then "
                         + "remembered that answer for thirty seconds")
    }

    func testASweepThatCouldNotBeTakenRefusesRatherThanReadingAsNoSessionRunning() {
        var thrown: CLIStateError?
        do {
            _ = try CLIState.configuration(liveConfigurations: nil, own: [:], home: home)
        } catch {
            thrown = error as? CLIStateError
        }

        guard case .liveSessionsUnreadable = thrown else {
            return XCTFail("a process table that could not be read used to arrive here as an empty "
                + "list of live sessions, which reads as nobody running and hands the switch our "
                + "own environment instead of refusing; got \(String(describing: thrown))")
        }
    }

    func testTheRememberedConfigurationExpiresAndCanBeForgotten() {
        let memo = RememberedCLIConfigurations()
        XCTAssertNil(memo.value(within: .seconds(30)), "nothing has been read yet")

        memo.keep([["CLAUDE_CONFIG_DIR": "/tmp/alt"]])
        XCTAssertEqual(memo.value(within: .seconds(30)), [["CLAUDE_CONFIG_DIR": "/tmp/alt"]])
        XCTAssertNil(memo.value(within: .seconds(0)),
                     "the account watch asks twice a second, so the sweep is remembered — but a "
                         + "stale answer must expire rather than outlive the sessions it came from")

        memo.forget()
        XCTAssertNil(memo.value(within: .seconds(30)),
                     "a switch forgets first, so the write never trusts a sweep older than itself")
    }

    func testTheCredentialNameIsThePlainOneWhenNoConfigurationHomeIsSet() {
        XCTAssertEqual(CLIState.credentialService(environment: [:]), "Claude Code-credentials",
                       "this is the name every machine here uses, and it must not move")
        XCTAssertEqual(CLIState.credentialService(environment: ["CLAUDE_CONFIG_DIR": ""]),
                       "Claude Code-credentials",
                       "an empty variable is not a configuration home, exactly as the CLI reads it")
    }

    func testARelativeConfigurationHomeNamesNoHomeToTheSlotEitherRatherThanOnlyToThePath() {
        let relative = ["CLAUDE_CONFIG_DIR": "relative/path"]

        XCTAssertEqual(CLIState.configDir(environment: relative, home: home).path,
                       home + "/.claude",
                       "the path resolver already decides that a value without a leading slash "
                           + "names no configuration home")
        XCTAssertEqual(CLIState.credentialService(environment: relative),
                       CLIState.credentialService(environment: [:]),
                       "so the slot name has to decide the same thing. Hashing a value the state "
                           + "file resolution ignored derives the credential from a home the account "
                           + "file was never read from, and keeping those two together is what this "
                           + "branch exists for")
    }

    func testWhitespaceAroundAConfigurationHomeIsNotPartOfTheSlotName() {
        XCTAssertEqual(CLIState.credentialService(environment: ["CLAUDE_CONFIG_DIR": "  /tmp/alt  "]),
                       CLIState.credentialService(environment: ["CLAUDE_CONFIG_DIR": "/tmp/alt"]),
                       "configDir and namedFileDirectory both trim before deciding, so a padded "
                           + "value resolves to the same directory and must resolve to the same slot")
    }

    func testAConfigurationHomeHashesIntoTheCredentialName() {
        let service = CLIState.credentialService(environment: ["CLAUDE_CONFIG_DIR": "/tmp/alt"])

        XCTAssertEqual(service, "Claude Code-credentials-\(Self.sha256Prefix("/tmp/alt"))",
                       "the CLI appends the first eight hex of sha256 over the configuration home, "
                           + "so a machine that sets the variable keeps its credential under a "
                           + "different name and a literal would read the wrong installation")
        XCTAssertNotEqual(service, "Claude Code-credentials")
    }

    func testTheHashIsOverTheValueVerbatimAndNotOverATidiedPath() {
        XCTAssertNotEqual(CLIState.credentialService(environment: ["CLAUDE_CONFIG_DIR": "/tmp/alt/"]),
                          CLIState.credentialService(environment: ["CLAUDE_CONFIG_DIR": "/tmp/alt"]),
                          "the CLI hashes the string it was given, so a trailing slash is a "
                              + "different name; standardising the path here would read the wrong item")
    }

    func testTheSecureStorageHomeWinsOverTheConfigurationHomeForTheCredentialName() {
        let service = CLIState.credentialService(environment: [
            "CLAUDE_CONFIG_DIR": "/tmp/alt",
            "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/tmp/secure",
        ])

        XCTAssertEqual(service, "Claude Code-credentials-\(Self.sha256Prefix("/tmp/secure"))")
        XCTAssertEqual(CLIState.credentialService(environment: [
            "CLAUDE_CONFIG_DIR": "/tmp/alt",
            "CLAUDE_SECURESTORAGE_CONFIG_DIR": "",
        ]), "Claude Code-credentials",
                       "defined but empty switches the hash off even though the other variable is set")
    }

    func testACustomOAuthURLMovesTheCredentialNameAsWellAsTheFilename() {
        XCTAssertEqual(
            CLIState.credentialService(environment: ["CLAUDE_CODE_CUSTOM_OAUTH_URL": "https://oauth.example"]),
            "Claude Code-custom-oauth-credentials",
            "the suffix sits before -credentials, and one function decides it for both the file and "
                + "the credential")
    }

    private static func sha256Prefix(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(8))
    }

    func testNothingIsGuessedWhenNeitherFileExists() {
        XCTAssertEqual(try picked([:], existing: []),
                       .missing(CLIState.stateFilesInOrder(environment: [:], home: home)))
    }

    func testTheWriteDropsAStaleUserIDWhenTheIncomingAccountHasNone() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-userid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("state.json")
        try JSONSerialization.data(withJSONObject: [
            "oauthAccount": ["emailAddress": "old@example.com"],
            "userID": "the-previous-account-user-id",
        ]).write(to: file)

        try CLIState.writeIdentity(
            CLIIdentity(oauthAccount: ["emailAddress": .string("new@example.com")],
                        userID: nil),
            to: file)

        let root = try JSONSerialization
            .jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
        XCTAssertNil(root["userID"], "the previous account's userID must not survive")
        XCTAssertEqual((root["oauthAccount"] as? [String: Any])?["emailAddress"] as? String,
                       "new@example.com")
    }

    func testTheWriteKeepsTheIncomingUserIDWhenItHasOne() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-userid2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("state.json")
        try JSONSerialization.data(withJSONObject: [
            "oauthAccount": ["emailAddress": "old@example.com"],
            "userID": "old-id",
        ]).write(to: file)

        try CLIState.writeIdentity(
            CLIIdentity(oauthAccount: ["emailAddress": .string("new@example.com")],
                        userID: "new-id"),
            to: file)

        let root = try JSONSerialization
            .jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
        XCTAssertEqual(root["userID"] as? String, "new-id")
    }

    func testTheWriteDropsTheCachesThatBelongToTheOutgoingAccount() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-caches-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("state.json")
        var before: [String: Any] = [
            "oauthAccount": ["emailAddress": "old@example.com"],
            "userID": "u1",
            "mcpServers": ["keep": "me"],
            "projects": ["also": "kept"],
        ]
        for key in CLIState.accountScopedCacheKeys { before[key] = "stale value for the old account" }
        try JSONSerialization.data(withJSONObject: before).write(to: file)

        try CLIState.writeIdentity(
            CLIIdentity(oauthAccount: ["emailAddress": .string("new@example.com")],
                        userID: "u2"),
            to: file)

        let root = try JSONSerialization
            .jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]

        XCTAssertFalse(CLIState.accountScopedCacheKeys.isEmpty)
        for key in CLIState.accountScopedCacheKeys {
            XCTAssertNil(root[key], "\(key) belongs to the account that just left")
        }
        XCTAssertEqual((root["oauthAccount"] as? [String: Any])?["emailAddress"] as? String,
                       "new@example.com")
        XCTAssertEqual((root["mcpServers"] as? [String: Any])?["keep"] as? String, "me")
        XCTAssertEqual((root["projects"] as? [String: Any])?["also"] as? String, "kept")
    }

    func testTheWriteGoesThroughASymlinkAndLeavesItStanding() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-link-\(UUID().uuidString)")
        let dir = base.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let real = dir.appendingPathComponent(".claude.json")
        try Data(#"{"oauthAccount": {"emailAddress": "old@example.com"}, "keep": "me"}"#.utf8)
            .write(to: real)
        let link = base.appendingPathComponent(".claude.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        try CLIState.writeIdentity(
            CLIIdentity(oauthAccount: ["emailAddress": .string("new@example.com")],
                        userID: "u2"),
            to: link)

        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))

        let root = try JSONSerialization
            .jsonObject(with: Data(contentsOf: real)) as? [String: Any]

        XCTAssertEqual((root?["oauthAccount"] as? [String: Any])?["emailAddress"] as? String,
                       "new@example.com")
        XCTAssertEqual(root?["keep"] as? String, "me")
    }

    func testOnlyAResolvedFileSurvivesRequireAndTheOtherNamesItsRemedy() {
        let one = URL(fileURLWithPath: "/tmp/alt.json")
        let two = URL(fileURLWithPath: "/tmp/alt/.claude.json")

        XCTAssertEqual(try CLIStateFile.resolved(one).require(), one)

        XCTAssertThrowsError(try CLIStateFile.missing([one, two]).require()) { error in
            let message = (error as? CLIStateError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("was not found"))
            XCTAssertTrue(message.contains(CLIState.configDirVariable))
        }
    }

    func testOnlyAResolvedFileHasAURLToReadFrom() {
        let one = URL(fileURLWithPath: "/tmp/alt.json")

        XCTAssertEqual(CLIStateFile.resolved(one).url, one)
        XCTAssertNil(CLIStateFile.missing([one]).url)
    }

    func testTheJournalNamesTheTwoCasesApart() {
        let one = URL(fileURLWithPath: "/tmp/alt.json")

        XCTAssertEqual(CLIStateFile.resolved(one).journalName, "resolved")
        XCTAssertEqual(CLIStateFile.missing([one]).journalName, "missing")
    }

    func testTheWriteLandsInTheFileItWasGivenAndLeavesTheOtherKeysAlone() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hats-write-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let given = dir.appendingPathComponent("not-a-candidate.json")
        try Data("""
        {"oauthAccount": {"emailAddress": "old@example.com"},
         "userID": "u1",
         "mcpServers": {"keep": "me"}}
        """.utf8).write(to: given)

        try CLIState.writeIdentity(
            CLIIdentity(oauthAccount: ["emailAddress": .string("new@example.com")],
                        userID: "u2"),
            to: given)

        let root = try JSONSerialization
            .jsonObject(with: Data(contentsOf: given)) as? [String: Any]
        let account = root?["oauthAccount"] as? [String: Any]

        XCTAssertEqual(account?["emailAddress"] as? String, "new@example.com")
        XCTAssertEqual(root?["userID"] as? String, "u2")
        XCTAssertEqual((root?["mcpServers"] as? [String: Any])?["keep"] as? String, "me")
    }


    func testTheRefusalNamesEveryPlaceItLookedAndTheVariable() {
        let message = CLIStateError
            .stateFileNotFound(["/tmp/alt.json", "/tmp/alt/.claude.json"])
            .errorDescription ?? ""

        XCTAssertTrue(message.contains("/tmp/alt.json"))
        XCTAssertTrue(message.contains("/tmp/alt/.claude.json"))
        XCTAssertTrue(message.contains("CLAUDE_CONFIG_DIR"))
    }

    func testTheUnreadableMessageNamesTheFileItFailedOn() {
        let message = CLIStateError.unreadable("/tmp/alt.json").errorDescription ?? ""

        XCTAssertTrue(message.contains("/tmp/alt.json"))
        XCTAssertFalse(message.contains("~/.claude.json"))
    }

    func testTheSecureStorageVariableSurvivesTheFilterAWriterReadsThrough() {
        let kept = CLIState.configuration(from: [
            "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/tmp/secure",
            "CLAUDE_CONFIG_DIR": "/tmp/alt",
            "PATH": "/usr/bin",
        ])

        XCTAssertEqual(kept, ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "/tmp/secure",
                              "CLAUDE_CONFIG_DIR": "/tmp/alt"],
                       "configKeys gates both the process read and this filter, so leaving the "
                           + "secure-storage variable out of it made the credential name's whole "
                           + "secure-storage branch dead in production while the unit checks passed "
                           + "by calling credentialService directly with a hand-built dictionary")
        XCTAssertTrue(CLIState.configKeys.contains(CLIState.secureStorageDirVariable))
        XCTAssertEqual(CLIState.credentialService(environment: kept),
                       CLIState.credentialService(environment: ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "/tmp/secure"]),
                       "and once it survives, it outranks the other variable as the CLI has it")
    }

    func testAWriterSweepsFreshAndOnlyAReaderMayUseTheMemory() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/CLIState.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        XCTAssertTrue(text.contains("configurationNow() throws -> CLIConfiguration {\n        try configuration(liveConfigurations: sweptNow(),"),
                      "configurationNow exists so that no operation is served a configuration older "
                          + "than itself - activate, capture and the login resolve which keychain "
                          + "slot to WRITE from it. Pointing it at the one-second memory was done "
                          + "once already, and writeVerified then confirms a write into whichever "
                          + "slot the stale answer named")
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats")
        let storeFiles = try FileManager.default
            .contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasPrefix("AccountStore") && $0.hasSuffix(".swift") }
            .sorted()
        XCTAssertFalse(storeFiles.isEmpty, "the store has to live somewhere")
        let storeText = try storeFiles
            .map { try String(contentsOf: sources.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
        let writersSweepingForThemselves = try NSRegularExpression(
            pattern: #"(activate|capture|reconcileWithLiveLogin)[\s\S]{0,400}?CLIState\.configurationNow\(\)"#
        )
        XCTAssertEqual(
            writersSweepingForThemselves.numberOfMatches(
                in: storeText, range: NSRange(storeText.startIndex..., in: storeText)
            ),
            3,
            "all three public entries of the store WRITE - each resolves which keychain slot and "
                + "which account file to write from the configuration it takes - so each takes its "
                + "own sweep. reconcileWithLiveLogin was moved to the remembered sweep while it goes "
                + "on writing through capture, which is a writer served an answer up to thirty "
                + "seconds older than itself"
        )

        let freshSweep = try NSRegularExpression(
            pattern: #"sweptNow\(\)[^{]*\{\s*swept\(SessionDiscovery\.everySessionThatHoldsAPort\(\)\)"#
        )
        XCTAssertEqual(freshSweep.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)), 1,
                       "and the fresh sweep must not be routed through the memory either. Matched by "
                           + "pattern rather than by the exact line, because the first version of "
                           + "this check pinned the return type too and failed the day that type "
                           + "gained a question mark, while the invariant it guards was untouched")
    }

    func testAChildThatIgnoresTheGentleSignalIsStillGoneWhenTheBudgetRunsOut() throws {
        let name = "hats-stubborn-\(UUID().uuidString.prefix(8)).sh"
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try "#!/bin/bash\ntrap '' TERM\nsleep 30\n".write(to: script, atomically: true,
                                                            encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                             ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }

        XCTAssertNil(ProcessTable.read([], within: 0.3, running: script.path),
                     "the budget runs out and the read refuses, as it did before")

        var alive = true
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, alive {
            Thread.sleep(forTimeInterval: 0.1)
            alive = Self.isRunning(named: name)
        }

        XCTAssertFalse(alive,
                       "measured rather than reasoned, which is what this claim needed: it was "
                           + "raised on the second review pass, refuted there by arguing that ps "
                           + "honours SIGTERM, and the ledger recorded that the refutation was "
                           + "reasoning. A child that ignores the gentle signal keeps the write end "
                           + "of the pipe open and the reader blocked with it, so the timeout path "
                           + "escalates")
    }

    func testTheEscalationIsAskedOfFoundationRatherThanOfTheBarePid() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/Sessions.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        XCTAssertTrue(text.contains("if process.isRunning { kill(process.processIdentifier, SIGKILL) }"),
                      "a pid can only be reused after the child has been reaped, and reaping is "
                          + "what turns Process.isRunning false — so asking Foundation closes the "
                          + "case where the signal would reach a stranger, while a bare "
                          + "kill(pid, 0) probe would only narrow it, the check and the signal being "
                          + "two steps. The race itself has no check here and is not claimed to")
    }

    private static func isRunning(named name: String) -> Bool {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        probe.arguments = ["-f", name]
        let out = Pipe()
        probe.standardOutput = out
        probe.standardError = Pipe()
        guard (try? probe.run()) != nil else { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        probe.waitUntilExit()
        return !data.isEmpty
    }
}
