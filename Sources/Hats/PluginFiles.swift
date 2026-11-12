import Darwin
import Foundation

enum PluginFiles {
    static let readCap = 4 << 20

    static func getContents(of path: String) -> PluginFileRead {
        var facts = stat()
        guard stat(path, &facts) == 0 else {
            if errno == ENOENT { return .missing }
            return .unreadable(String(cString: strerror(errno)))
        }
        guard facts.st_mode & S_IFMT == S_IFREG else { return .unreadable("it is not a regular file") }
        guard facts.st_size <= readCap else { return .unreadable("it is larger than \(readCap >> 20) MB") }
        do {
            return .read(try Data(contentsOf: URL(fileURLWithPath: path)))
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    static func isDirectory(_ path: String) -> Bool {
        var facts = stat()
        guard stat(path, &facts) == 0 else { return false }

        return facts.st_mode & S_IFMT == S_IFDIR
    }

    static func isExecutableFile(_ path: String) -> Bool {
        var facts = stat()
        guard stat(path, &facts) == 0, facts.st_mode & S_IFMT == S_IFREG else { return false }

        return access(path, X_OK) == 0
    }

    static func isSameFile(_ first: String, _ second: String) -> Bool {
        var one = stat()
        var other = stat()
        guard stat(first, &one) == 0, stat(second, &other) == 0 else { return false }

        return one.st_dev == other.st_dev && one.st_ino == other.st_ino
    }
}

typealias PathTest = (String) -> Bool

enum InstalledCLIs {
    static func find(
        home: String,
        environment: [String: String],
        isExecutable: PathTest
    ) -> [String] {
        let known = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home + "/.local/bin/claude",
            home + "/.claude/local/claude",
        ]
        let onPath = (environment["PATH"] ?? "")
            .split(separator: ":")
            .filter { $0.hasPrefix("/") }
            .map { String($0) + "/claude" }
        var seen: Set<String> = []
        var found: [String] = []
        for candidate in known + onPath where isExecutable(candidate) {
            let real = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            guard seen.insert(real).inserted else { continue }
            found.append(candidate)
        }

        return found
    }
}
