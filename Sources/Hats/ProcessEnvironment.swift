import Foundation

enum ProcessEnvironmentRead: Equatable {
    case read([String: String])
    case processGone
    case unreadable

    var values: [String: String]? {
        guard case .read(let values) = self else { return nil }
        return values
    }
}

enum ProcessEnvironment {
    private static let argmax: Int? = {
        var name: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&name, 2, &value, &size, nil, 0) == 0, value > 0 else { return nil }
        return Int(value)
    }()

    static func read(pid: Int32, keeping wanted: Set<String>? = nil) -> ProcessEnvironmentRead {
        guard let argmax else { return .unreadable }
        var name: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var buffer = [UInt8](repeating: 0, count: argmax)
        var size = buffer.count
        guard sysctl(&name, 3, &buffer, &size, nil, 0) == 0 else {
            return isRunning(pid) ? .unreadable : .processGone
        }
        guard let values = parsed(procargs: Array(buffer.prefix(size)), keeping: wanted) else {
            return .unreadable
        }
        return .read(values)
    }

    static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func parsed(procargs bytes: [UInt8], keeping wanted: Set<String>? = nil) -> [String: String]? {
        guard bytes.count >= 4 else { return nil }
        let argc = Int(bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        guard argc >= 0 else { return nil }

        var index = 4
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }

        let strings = terminatedStrings(in: bytes[index...])
        guard strings.count >= argc else { return nil }

        return environment(from: strings.dropFirst(argc), keeping: wanted)
    }

    private static func terminatedStrings(in bytes: ArraySlice<UInt8>) -> [String] {
        var strings: [String] = []
        var start = bytes.startIndex
        for index in bytes.indices where bytes[index] == 0 {
            strings.append(String(bytes: bytes[start..<index], encoding: .utf8) ?? "")
            start = index + 1
        }
        return strings
    }

    private static func environment(
        from strings: ArraySlice<String>,
        keeping wanted: Set<String>?
    ) -> [String: String] {
        var environment: [String: String] = [:]
        for entry in strings {
            guard let equals = entry.firstIndex(of: "="), equals != entry.startIndex else { continue }
            let name = String(entry[..<equals])
            guard wanted?.contains(name) ?? true, environment[name] == nil else { continue }
            environment[name] = String(entry[entry.index(after: equals)...])
        }
        return environment
    }
}
