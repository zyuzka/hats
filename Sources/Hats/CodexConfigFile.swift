import Darwin
import Foundation

enum CodexConfigOutcome: Equatable {
    case unchanged
    case written
    case removed
    case foreign(String)
    case unsupported
}

struct CodexConfigFile {
    static let attempts = 3

    let url: URL
    var rename: (URL, URL) throws -> Void = CodexHome.systemRename
    var beforeRename: (() -> Void)?
    var journalName = "codexGateway.config"

    func apply(_ edit: (String?) -> CodexConfigEdit) throws -> CodexConfigOutcome {
        for attempt in 1...Self.attempts {
            let path = try target()
            let original = try read(path)
            switch edit(original) {
            case .unchanged:
                return .unchanged
            case .foreign(let value):
                return .foreign(value)
            case .unsupported:
                return .unsupported
            case .emptied:
                guard try read(path) == original else { continue }
                try FileManager.default.removeItem(at: path)
                return .removed
            case .changed(let text):
                let temporary = try writeTemporary(text, beside: path)
                beforeRename?()
                guard try read(path) == original else {
                    unlink(temporary.path)
                    Journal.log("\(journalName).changedMeanwhile", ["attempt": String(attempt)])
                    continue
                }
                do {
                    try rename(temporary, path)
                } catch {
                    unlink(temporary.path)
                    throw error
                }
                guard try read(path) == text else {
                    Journal.log("\(journalName).readBackDiffered", ["attempt": String(attempt)])
                    continue
                }
                return .written
            }
        }
        Journal.log("\(journalName).gaveUp")
        throw CodexError.writeFailed("config.toml kept changing while Hats wrote it")
    }

    func target() throws -> URL {
        var current = url
        for _ in 0..<8 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else {
                return current
            }
            current = URL(fileURLWithPath: destination, relativeTo: current.deletingLastPathComponent())
                .standardizedFileURL
        }
        throw CodexError.writeFailed("config.toml is a chain of links Hats does not follow")
    }

    func read(_ path: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexError.writeFailed("config.toml is not UTF-8 text")
        }
        return text
    }

    func writeTemporary(_ text: String, beside path: URL) throws -> URL {
        let folder = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var info = stat()
        let mode = stat(path.path, &info) == 0 ? mode_t(info.st_mode & 0o777) : 0o644
        let temporary = folder.appendingPathComponent(".config-hats-\(UUID().uuidString)")
        let fd = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY, mode)
        guard fd >= 0 else { throw CodexError.writeFailed(String(cString: strerror(errno))) }
        let data = Data(text.utf8)
        var failure: String?
        data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let count = Darwin.write(fd, raw.baseAddress?.advanced(by: sent), raw.count - sent)
                guard count > 0 else {
                    failure = String(cString: strerror(errno))
                    return
                }
                sent += count
            }
        }
        if failure == nil, fchmod(fd, mode) != 0 || fsync(fd) != 0 { failure = String(cString: strerror(errno)) }
        Darwin.close(fd)
        guard let failure else { return temporary }
        unlink(temporary.path)
        throw CodexError.writeFailed(failure)
    }
}
