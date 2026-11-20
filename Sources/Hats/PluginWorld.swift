import Foundation

struct LiveCLISession: Equatable {
    let pid: Int32
    let executable: String?
    let environment: [String: String]
}

enum PluginFileRead: Equatable {
    case missing
    case unreadable(String)
    case read(Data)
}

struct PluginWorld {
    var run: (PluginCommandLine) -> PluginCommandOutcome
    var liveSessions: () -> [LiveCLISession]?
    var installedCLIs: () -> [String]
    var readFile: (String) -> PluginFileRead
    var isDirectory: (String) -> Bool
    var isExecutableFile: (String) -> Bool
    var isSameFile: (String, String) -> Bool
    var ownEnvironment: () -> [String: String]
    var home: () -> String
    var compareCopy: (_ copy: String, _ folder: String) -> CodexCopyState = { _, _ in
        .unreadable("this world cannot compare folders")
    }

    static let real = PluginWorld(
        run: { GroupRun.getOutcome(of: $0) },
        liveSessions: { LiveCLISessions.find() },
        installedCLIs: {
            InstalledCLIs.find(
                home: NSHomeDirectory(),
                environment: ProcessInfo.processInfo.environment,
                isExecutable: PluginFiles.isExecutableFile
            )
        },
        readFile: { PluginFiles.getContents(of: $0) },
        isDirectory: { PluginFiles.isDirectory($0) },
        isExecutableFile: { PluginFiles.isExecutableFile($0) },
        isSameFile: { PluginFiles.isSameFile($0, $1) },
        ownEnvironment: { ProcessInfo.processInfo.environment },
        home: { NSHomeDirectory() },
        compareCopy: { CodexPluginCopy.compare(copy: $0, folder: $1) }
    )
}
