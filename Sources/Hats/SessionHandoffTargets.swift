import Foundation

enum SessionHandoffTargets {
    static let commandSeconds: TimeInterval = 30
    static let sessionVariables = [
        "CLAUDECODE",
        "CLAUDE_CODE_CHILD_SESSION",
        "CLAUDE_CODE_ENTRYPOINT",
        "CLAUDE_CODE_EXECPATH",
    ]

    static func find(in world: PluginWorld) -> Result<SessionHandoffTarget, SessionHandoffRefusal> {
        guard let sessions = world.liveSessions() else { return .failure(.sessionsUnreadable) }
        let home = world.home()
        let own = world.ownEnvironment()
        var configurations: [[String: String]] = []
        for session in sessions {
            let kept = CLIState.configuration(from: session.environment)
            if !configurations.contains(kept) { configurations.append(kept) }
        }
        guard let inForce = CLIState.configurationInForce(liveConfigurations: configurations, own: own) else {
            return .failure(getDisagreement(configurations, home: home))
        }
        let folder: String
        switch getConfigFolder(inForce.configuration, home: home) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let found): folder = found
        }
        guard world.isDirectory(folder) else { return .failure(.noConfigFolder(folder)) }
        guard let chosen = findCLI(
            sessions: sessions,
            world: world,
            own: own,
            variables: inForce.configuration
        ) else {
            return .failure(.noCLI)
        }

        return .success(SessionHandoffTarget(
            cli: chosen.path,
            configFolder: folder,
            environment: chosen.environment,
            sessionPath: chosen.session?.environment[LiveCLISessions.pathVariable]
        ))
    }

    static func getDisagreement(_ configurations: [[String: String]], home: String) -> SessionHandoffRefusal {
        var folders: [String] = []
        for configuration in configurations {
            let folder: String
            switch getConfigFolder(configuration, home: home) {
            case .success(let found): folder = found
            case .failure: folder = configuration[CLIState.configDirVariable] ?? ""
            }
            if !folders.contains(folder) { folders.append(folder) }
        }
        guard folders.count == 1 else { return .sessionsDisagree(folders.sorted()) }
        let names = CLIState.configKeys.filter { key in
            Set(configurations.map { $0[key] ?? "" }).count > 1
        }

        return .sessionsDisagreeOnVariables(names.sorted())
    }

    static func getConfigFolder(
        _ variables: [String: String],
        home: String
    ) -> Result<String, SessionHandoffRefusal> {
        guard let named = variables[CLIState.configDirVariable] else {
            return .success(URL(fileURLWithPath: home).appendingPathComponent(".claude").path)
        }
        guard named.hasPrefix("/") else { return .failure(.relativeConfigFolder(named)) }

        return .success(URL(fileURLWithPath: named).standardizedFileURL.path)
    }

    static func createEnvironment(
        own: [String: String],
        variables: [String: String],
        path: String?
    ) -> [String: String] {
        var environment = own
        for key in sessionVariables { environment.removeValue(forKey: key) }
        for key in CLIState.configKeys { environment.removeValue(forKey: key) }
        environment.merge(variables) { _, chosen in chosen }
        if let path { environment[LiveCLISessions.pathVariable] = path }

        return environment
    }

    static func findCLI(
        sessions: [LiveCLISession],
        world: PluginWorld,
        own: [String: String],
        variables: [String: String]
    ) -> SessionHandoffCLI? {
        var fromSessions: [SessionHandoffCLI] = []
        for session in sessions {
            guard let path = session.executable, !fromSessions.contains(where: { $0.path == path }) else { continue }
            fromSessions.append(SessionHandoffCLI(
                path: path,
                session: session,
                environment: createEnvironment(
                    own: own,
                    variables: variables,
                    path: session.environment[LiveCLISessions.pathVariable]
                )
            ))
        }
        let ownPath = own[LiveCLISessions.pathVariable].map { ":" + $0 } ?? ""
        let installed = world.installedCLIs().map { path in
            SessionHandoffCLI(
                path: path,
                session: nil,
                environment: createEnvironment(
                    own: own,
                    variables: variables,
                    path: URL(fileURLWithPath: path).deletingLastPathComponent().path + ownPath
                )
            )
        }

        return findNewest(fromSessions, in: world) ?? findNewest(installed, in: world)
    }

    static func findNewest(_ candidates: [SessionHandoffCLI], in world: PluginWorld) -> SessionHandoffCLI? {
        var best: (cli: SessionHandoffCLI, version: [Int])?
        for candidate in candidates {
            let outcome = world.run(PluginCommandLine(
                executable: candidate.path,
                arguments: ["--version"],
                environment: candidate.environment,
                seconds: commandSeconds
            ))
            guard outcome.end == .exited(0), let version = getVersion(outcome.stdoutText ?? "") else { continue }
            if let held = best, !held.version.lexicographicallyPrecedes(version) { continue }
            best = (candidate, version)
        }

        return best?.cli
    }

    static func getVersion(_ text: String) -> [Int]? {
        guard let token = text.split(whereSeparator: \.isWhitespace).first else { return nil }
        let parts = token.split(separator: ".").map { Int($0) }
        guard parts.count >= 2, !parts.contains(nil) else { return nil }

        return parts.compactMap { $0 }
    }
}
