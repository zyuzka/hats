import Darwin
import Foundation

enum CodexNotes {
    static let folderName = "hats-codex-notes"

    static var folder: URL {
        let temporary = ProcessInfo.processInfo.environment["TMPDIR"].flatMap { $0.isEmpty ? nil : $0 } ?? "/tmp"

        return URL(fileURLWithPath: temporary).appendingPathComponent(folderName)
    }

    static func hasNote(for session: String, in folder: URL) -> Bool {
        guard CodexContinue.isASessionID(session), isOwnPrivateFolder(folder) else { return false }
        var info = stat()
        guard lstat(folder.appendingPathComponent(session + ".md").path, &info) == 0 else { return false }

        return info.st_mode & S_IFMT == S_IFREG
    }

    static func isOwnPrivateFolder(_ folder: URL) -> Bool {
        var info = stat()
        guard lstat(folder.path, &info) == 0 else { return false }
        let isFolder = info.st_mode & S_IFMT == S_IFDIR
        let isPrivate = info.st_mode & 0o777 == 0o700

        return isFolder && isPrivate && info.st_uid == getuid()
    }
}
