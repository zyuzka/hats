import Darwin
import Foundation

struct CodexHome {
    let url: URL
    var lockWait: TimeInterval = 10
    var rename: (URL, URL) throws -> Void = CodexHome.systemRename

    static var real: CodexHome {
        CodexHome(url: location(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory()))
    }

    static func location(environment: [String: String], home: String) -> URL {
        if let set = environment["CODEX_HOME"], !set.isEmpty { return URL(fileURLWithPath: set) }
        if let state = environment[StateDirectory.overrideName], !state.isEmpty {
            return URL(fileURLWithPath: state).appendingPathComponent("codex")
        }

        return URL(fileURLWithPath: home).appendingPathComponent(".codex")
    }

    var auth: URL { url.appendingPathComponent("auth.json") }
    var config: URL { url.appendingPathComponent("config.toml") }
    var locks: [URL] { [url.appendingPathComponent("auth.lock"), url.appendingPathComponent("auth.json.lock")] }

    static let storeKey = "cli_auth_credentials_store"

    static func systemRename(_ from: URL, _ to: URL) throws {
        guard Darwin.rename(from.path, to.path) == 0 else {
            throw CodexError.writeFailed(String(cString: strerror(errno)))
        }
    }

    func requireFileStore() throws {
        guard FileManager.default.fileExists(atPath: config.path) else { return }
        guard let text = try? String(contentsOf: config, encoding: .utf8) else {
            throw CodexError.notStoredInAFile("config.toml could not be read")
        }
        guard let mode = Self.storeMode(in: text), mode != "file" else { return }
        throw CodexError.notStoredInAFile("\(Self.storeKey) is \(mode)")
    }

    static func storeMode(in text: String) -> String? {
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
                .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            if line.hasPrefix("[") { return nil }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let key = parts.first?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard parts.count == 2, key == storeKey else { continue }

            return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }

        return nil
    }

    func readLive() throws -> Data? {
        var info = stat()
        guard lstat(auth.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw CodexError.liveUnreadable(String(cString: strerror(errno)))
        }
        let kind = info.st_mode & S_IFMT
        guard kind != S_IFLNK else { throw CodexError.liveUnusable("it is a link") }
        guard kind == S_IFREG else { throw CodexError.liveUnusable("it is not a plain file") }
        guard info.st_nlink <= 1 else { throw CodexError.liveUnusable("it has \(info.st_nlink) hard links") }
        guard access(auth.path, W_OK) == 0 else { throw CodexError.liveUnusable("it is read-only") }
        do {
            return try Data(contentsOf: auth)
        } catch {
            throw CodexError.liveUnreadable(error.localizedDescription)
        }
    }

    func readLiveChecked() throws -> Data? {
        guard let data = try readLive() else { return nil }
        switch CodexAuth.problem(of: data) {
        case .notJSON: throw CodexError.liveUnusable("it is not valid JSON")
        case .notChatGPT: throw CodexError.liveUnusable("it is not a ChatGPT login")
        default: return data
        }
    }

    func permissions() -> Int? {
        var info = stat()
        guard lstat(auth.path, &info) == 0 else { return nil }
        return Int(info.st_mode & 0o777)
    }
}
