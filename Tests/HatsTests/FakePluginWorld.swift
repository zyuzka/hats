import Foundation
@testable import Hats

final class FakePluginWorld {
    static let home = "/Users/someone"
    static let cli = "/Users/someone/.local/bin/claude"
    static let configFolder = "/Users/someone/.claude"
    static let settings = "/Users/someone/.claude/settings.json"
    static let shell = "/bin/zsh"
    static let homebrewPython = "/opt/homebrew/bin/python3"

    var sessions: [LiveCLISession]? = []
    var installed = [cli]
    var files: [String: PluginFileRead] = [:]
    var directories: Set<String> = [configFolder]
    var executables: Set<String> = []
    var sameFiles: Set<String> = []
    var environment = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "SHELL": shell,
    ]
    var answers: [String: PluginCommandOutcome] = [:]
    var queued: [String: [PluginCommandOutcome]] = [:]
    var runs: [PluginCommandLine] = []
    var whenRunning: ((PluginCommandLine) -> Void)?
    var copies: [String: CodexCopyState] = [:]
    var compared: [String] = []

    static func key(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments).joined(separator: " ")
    }

    static func claude(_ arguments: [String]) -> String { key(cli, arguments) }

    init() {
        answer(Self.claude(["--version"]), PluginCLISamples.version322)
        answer(Self.claude(SessionHandoffSteps.helpArguments), PluginCLISamples.installHelp322)
        answer(Self.claude(SessionHandoffUpdateSteps.helps[0].arguments), PluginCLISamples.marketplaceUpdateHelp322)
        answer(Self.claude(SessionHandoffUpdateSteps.helps[1].arguments), PluginCLISamples.updateHelp322)
        answer(Self.claude(SessionHandoffSteps.listArguments), PluginCLISamples.listEmpty)
        answer(Self.claude(SessionHandoffSteps.marketplaceArguments), PluginCLISamples.marketplacesEmpty)
        answers[Self.key(Self.shell, ["-lc", "command -v python3"])] = Self.printed(Self.homebrewPython + "\n")
    }

    func answer(_ key: String, _ sample: PluginCLISample) {
        answers[key] = sample.outcome
    }

    func queue(_ key: String, _ outcomes: [PluginCommandOutcome]) {
        queued[key] = outcomes
    }

    static func printed(_ text: String, code: Int32 = 0) -> PluginCommandOutcome {
        PluginCommandOutcome(end: .exited(code), stdout: Data(text.utf8))
    }

    var changingRuns: [PluginCommandLine] {
        runs.filter { line in
            line.arguments.starts(with: ["plugin", "install"]) && !line.arguments.contains("--help")
                || line.arguments.starts(with: ["plugin", "uninstall"])
                || line.arguments.starts(with: ["plugin", "marketplace", "add"])
                || line.arguments.starts(with: ["plugin", "marketplace", "remove"])
                || line.arguments.starts(with: ["plugin", "update"]) && !line.arguments.contains("--help")
                || line.arguments.starts(with: ["plugin", "marketplace", "update"]) && !line.arguments.contains("--help")
                || line.arguments.starts(with: ["plugin", "add"])
                || line.arguments.starts(with: ["plugin", "remove"])
                || line.arguments.starts(with: ["plugin", "marketplace", "upgrade"])
        }
    }

    var commands: [String] { runs.map { Self.key($0.executable, $0.arguments) } }

    func world() -> PluginWorld {
        PluginWorld(
            run: { [self] line in
                self.runs.append(line)
                self.whenRunning?(line)
                let key = Self.key(line.executable, line.arguments)
                if var waiting = self.queued[key], !waiting.isEmpty {
                    let next = waiting.removeFirst()
                    self.queued[key] = waiting
                    return next
                }
                return self.answers[key] ?? PluginCommandOutcome(end: .notStarted("the fake has no answer for \(key)"))
            },
            liveSessions: { [self] in self.sessions },
            installedCLIs: { [self] in self.installed },
            readFile: { [self] path in self.files[path] ?? .missing },
            isDirectory: { [self] path in self.directories.contains(path) },
            isExecutableFile: { [self] path in self.executables.contains(path) },
            isSameFile: { [self] first, second in
                first == second || self.sameFiles.contains(first + "=" + second)
            },
            ownEnvironment: { [self] in self.environment },
            home: { Self.home },
            compareCopy: { [self] copy, folder in
                self.compared.append(copy + "=" + folder)
                return self.copies[copy + "=" + folder] ?? .unreadable("the fake has no comparison for \(copy)")
            }
        )
    }
}
