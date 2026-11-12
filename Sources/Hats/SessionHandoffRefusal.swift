import Foundation

enum SessionHandoffRefusal: Error, Equatable {
    case sessionsUnreadable
    case sessionsDisagree([String])
    case sessionsDisagreeOnVariables([String])
    case relativeConfigFolder(String)
    case noConfigFolder(String)
    case noCLI
    case pythonMissing(String)
    case pythonPlaceholder(String)
    case pythonUnchecked(String)
    case oldHook(file: String, commands: [String])
    case brokenSettings(file: String, reason: String)
    case cliTooOld(path: String, command: String, option: String)
    case cliDidNotAnswer(command: String, reason: String)
    case notOurs(String)
}

struct SessionHandoffTarget: Equatable {
    let cli: String
    let configFolder: String
    let environment: [String: String]
    let sessionPath: String?

    func createLine(_ arguments: [String], seconds: TimeInterval) -> PluginCommandLine {
        PluginCommandLine(
            executable: cli,
            arguments: arguments,
            environment: environment,
            seconds: seconds
        )
    }
}

struct SessionHandoffCLI: Equatable {
    let path: String
    let session: LiveCLISession?
    let environment: [String: String]
}
