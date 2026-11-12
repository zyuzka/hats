import Foundation

struct SessionHandoffPythonFound: Equatable {
    let path: String
    let isFromTheLoginShell: Bool
}

enum SessionHandoffPython {
    static let systemPython = "/usr/bin/python3"
    static let xcodeSelect = "/usr/bin/xcode-select"
    static let fallbackShell = "/bin/zsh"
    static let shellSeconds: TimeInterval = 10

    static func find(
        for target: SessionHandoffTarget,
        in world: PluginWorld
    ) -> Result<SessionHandoffPythonFound, SessionHandoffRefusal> {
        let looked: Result<SessionHandoffPythonFound, SessionHandoffRefusal>
        if let path = target.sessionPath {
            looked = findOnPath(path, in: world)
        } else {
            looked = findThroughTheLoginShell(target, in: world)
        }
        guard case .success(let found) = looked else { return looked }
        guard world.isSameFile(found.path, systemPython) else { return looked }
        let check = world.run(PluginCommandLine(
            executable: xcodeSelect,
            arguments: ["-p"],
            environment: target.environment,
            seconds: shellSeconds
        ))
        switch check.end {
        case .exited(0):
            return looked
        case .exited:
            return .failure(.pythonPlaceholder(found.path))
        case .signalled, .timedOut, .notStarted:
            return .failure(.pythonUnchecked("\(xcodeSelect) -p: \(check.trouble ?? "no answer")"))
        }
    }

    static func findOnPath(
        _ path: String,
        in world: PluginWorld
    ) -> Result<SessionHandoffPythonFound, SessionHandoffRefusal> {
        for folder in path.split(separator: ":") where folder.hasPrefix("/") {
            let candidate = String(folder) + "/python3"
            guard world.isExecutableFile(candidate) else { continue }
            return .success(SessionHandoffPythonFound(path: candidate, isFromTheLoginShell: false))
        }

        return .failure(.pythonMissing("the PATH of the running Claude Code session"))
    }

    static func findThroughTheLoginShell(
        _ target: SessionHandoffTarget,
        in world: PluginWorld
    ) -> Result<SessionHandoffPythonFound, SessionHandoffRefusal> {
        let named = world.ownEnvironment()["SHELL"] ?? ""
        let shell = named.hasPrefix("/") ? named : fallbackShell
        let outcome = world.run(PluginCommandLine(
            executable: shell,
            arguments: [
                "-lc",
                "command -v python3",
            ],
            environment: target.environment,
            seconds: shellSeconds
        ))
        guard case .exited(let code) = outcome.end else {
            return .failure(.pythonUnchecked("\(shell) did not finish looking for python3: \(outcome.trouble ?? "")"))
        }
        let found = (outcome.stdoutText ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") }
        guard code == 0, let found else {
            return .failure(.pythonMissing("a new login shell (\(shell))"))
        }

        return .success(SessionHandoffPythonFound(path: found, isFromTheLoginShell: true))
    }
}
