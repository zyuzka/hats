import Foundation

struct CodexPluginTarget: Equatable {
    let cli: String
    let codexHome: String
    let environment: [String: String]

    func createLine(_ arguments: [String], seconds: TimeInterval) -> PluginCommandLine {
        PluginCommandLine(
            executable: cli,
            arguments: arguments,
            environment: environment,
            seconds: seconds
        )
    }
}

enum CodexPluginTargets {
    static let fallbackShell = "/bin/zsh"
    static let shellSeconds: TimeInterval = 10
    static let pathMarker = "__HATS_PATH__"
    static let printPath = "printf '\\n\(pathMarker)%s' \"$PATH\""

    static func getKnownFolders(home: String) -> [String] {
        [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            home + "/.local/bin",
        ]
    }

    static func find(in world: PluginWorld) -> CodexPluginTarget? {
        let home = world.home()
        let own = world.ownEnvironment()
        if let cli = findCLI(in: getKnownFolders(home: home), world: world) {
            return createTarget(cli: cli, path: own["PATH"], world: world)
        }
        guard let shellPath = findLoginShellPath(in: world),
              let cli = findCLI(in: getFolders(shellPath), world: world) else { return nil }

        return createTarget(cli: cli, path: shellPath, world: world)
    }

    static func findCLI(in folders: [String], world: PluginWorld) -> String? {
        folders.map { $0 + "/codex" }.first(where: world.isExecutableFile)
    }

    static func getFolders(_ path: String) -> [String] {
        path.split(separator: ":").filter { $0.hasPrefix("/") }.map(String.init)
    }

    static func findLoginShellPath(in world: PluginWorld) -> String? {
        let named = world.ownEnvironment()["SHELL"] ?? ""
        let shell = named.hasPrefix("/") ? named : fallbackShell
        let outcome = world.run(PluginCommandLine(
            executable: shell,
            arguments: [
                "-lc",
                printPath,
            ],
            environment: world.ownEnvironment(),
            seconds: shellSeconds
        ))
        guard outcome.end == .exited(0), let text = outcome.stdoutText else { return nil }

        return getPath(fromShellOutput: text)
    }

    static func getPath(fromShellOutput text: String) -> String? {
        guard let marker = text.range(of: pathMarker, options: .backwards) else { return nil }
        let printed = text[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let folders = !printed.contains(":") && printed.contains(" ")
            ? printed.split(separator: " ").map(String.init)
            : [printed]
        let path = folders.joined(separator: ":")

        return path.isEmpty ? nil : path
    }

    static func createTarget(cli: String, path: String?, world: PluginWorld) -> CodexPluginTarget {
        let folder = URL(fileURLWithPath: cli).deletingLastPathComponent().path
        let codexHome = CodexHome.location(environment: world.ownEnvironment(), home: world.home()).path
        var environment = world.ownEnvironment()
        let rest = (path ?? "").split(separator: ":").map(String.init)
        environment["PATH"] = (rest.contains(folder) ? rest : [folder] + rest).joined(separator: ":")
        environment["CODEX_HOME"] = codexHome

        return CodexPluginTarget(cli: cli, codexHome: codexHome, environment: environment)
    }
}
