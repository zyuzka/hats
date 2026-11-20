import Darwin
import Foundation

enum CodexPluginCopy {
    static let ignoredNames: Set<String> = [
        "__pycache__",
        ".DS_Store",
    ]
    static let entryCap = 1000
    static let fileCap = 4 << 20
    static let totalCap = 32 << 20

    enum Entry: Equatable {
        case folder
        case file(Data)
        case link(String)
    }

    static func getCachePath(codexHome: String, version: String) -> String {
        URL(fileURLWithPath: codexHome)
            .appendingPathComponent("plugins/cache")
            .appendingPathComponent(CodexPluginProvenance.marketplaceName)
            .appendingPathComponent(CodexPluginProvenance.pluginName)
            .appendingPathComponent(version)
            .path
    }

    static func compare(copy: String, folder: String) -> CodexCopyState {
        var info = stat()
        if lstat(copy, &info) != 0, errno == ENOENT { return .differs("Codex has no copy at \(copy)") }
        let copied: [String: Entry]
        switch findEntries(under: copy) {
        case .failure(let trouble): return .unreadable("Codex's copy \(copy) could not be read: \(trouble.text)")
        case .success(let found): copied = found
        }
        let original: [String: Entry]
        switch findEntries(under: folder) {
        case .failure(let trouble): return .unreadable("the folder \(folder) could not be read: \(trouble.text)")
        case .success(let found): original = found
        }
        let names = Set(copied.keys).symmetricDifference(original.keys).sorted()
        if let name = names.first {
            let side = copied[name] == nil ? "is only in the folder" : "is only in Codex's copy"
            return .differs("\(name) \(side)")
        }
        if let name = original.keys.sorted().first(where: { original[$0] != copied[$0] }) {
            return .differs("\(name) differs")
        }

        return .same
    }

    static func findEntries(under root: String) -> Result<[String: Entry], SessionHandoffTrouble> {
        var info = stat()
        guard stat(root, &info) == 0 else { return .failure(.unreadable(String(cString: strerror(errno)))) }
        guard info.st_mode & S_IFMT == S_IFDIR else { return .failure(.unreadable("it is not a folder")) }
        var walk = Walk()
        if let trouble = walk.visit(root, relative: "") { return .failure(.unreadable(trouble)) }

        return .success(walk.entries)
    }

    struct Walk {
        var entries: [String: Entry] = [:]
        var total = 0

        mutating func visit(_ folder: String, relative: String) -> String? {
            let names: [String]
            do {
                names = try FileManager.default.contentsOfDirectory(atPath: folder).sorted()
            } catch {
                return error.localizedDescription
            }
            for name in names where !CodexPluginCopy.ignoredNames.contains(name) {
                let path = folder + "/" + name
                let key = relative.isEmpty ? name : relative + "/" + name
                if let trouble = add(path, key: key) { return trouble }
            }

            return nil
        }

        mutating func add(_ path: String, key: String) -> String? {
            guard entries.count < CodexPluginCopy.entryCap else {
                return "it holds more than \(CodexPluginCopy.entryCap) entries"
            }
            var info = stat()
            guard lstat(path, &info) == 0 else { return "\(key): " + String(cString: strerror(errno)) }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                entries[key] = .folder
                return visit(path, relative: key)
            case S_IFLNK:
                return addLink(path, key: key)
            case S_IFREG:
                return addFile(path, key: key, size: Int(info.st_size))
            default:
                return "\(key) is neither a file, a folder nor a link"
            }
        }

        mutating func addLink(_ path: String, key: String) -> String? {
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
                return "\(key): the link could not be read"
            }
            entries[key] = .link(target)

            return nil
        }

        mutating func addFile(_ path: String, key: String, size: Int) -> String? {
            guard size <= CodexPluginCopy.fileCap else { return "\(key) is larger than 4 MB" }
            total += size
            guard total <= CodexPluginCopy.totalCap else { return "its files are larger than 32 MB together" }
            guard let data = FileManager.default.contents(atPath: path) else { return "\(key) could not be read" }
            entries[key] = .file(data)

            return nil
        }
    }
}
