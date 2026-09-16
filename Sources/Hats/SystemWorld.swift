import Foundation

struct SystemWorld {
    var processTable: ([String], TimeInterval) -> String?
    var processEnvironment: (Int32, Set<String>?) -> ProcessEnvironmentRead
    var isTheRealCLI: (Int32) -> Bool?
    var cliStatus: () -> CLI.Status?
    var ownEnvironment: () -> [String: String]
    var home: () -> String

    static let real = SystemWorld(
        processTable: { ProcessTable.read($0, within: $1) },
        processEnvironment: { ProcessEnvironment.read(pid: $0, keeping: $1) },
        isTheRealCLI: { TrustedCLI.isTheRealCLI(pid: $0) },
        cliStatus: { CLI.status() },
        ownEnvironment: { ProcessInfo.processInfo.environment },
        home: { NSHomeDirectory() }
    )
}
