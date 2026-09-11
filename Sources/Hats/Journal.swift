import Foundation

enum Journal {
    static var url: URL {
        StateDirectory.url.appendingPathComponent("operations.log")
    }

    static let ours = "dev.tmk.hats"

    private static let writing = NSLock()

    static var destination: JournalDestination {
        JournalDestination.of(bundleIdentifier: Bundle.main.bundleIdentifier, ours: ours)
    }

    static func fingerprint(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "empty" }
        var hash: [UInt8] = Array(repeating: 0, count: 32)
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            h ^= UInt64(byte)
            h = h &* 0x100_0000_01b3
        }
        withUnsafeBytes(of: h.bigEndian) { raw in
            for (i, b) in raw.enumerated() where i < 32 { hash[i] = b }
        }
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func onOneLine(_ value: String) -> String {
        String(value.map { character in
            character.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
                ? " "
                : character
        })
    }

    static func line(_ operation: String, _ details: [String: String], at stamp: String) -> String {
        let rendered = details
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(onOneLine($0.value))" }
            .joined(separator: " ")

        return "\(stamp) \(operation) \(rendered)\n"
    }

    static func log(_ operation: String, _ details: [String: String] = [:]) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = Self.line(operation, details, at: stamp)

        guard let data = line.data(using: .utf8) else { return }
        writing.lock()
        defer { writing.unlock() }
        guard destination == .theOperatorsLog else {
            FileHandle.standardError.write(data)
            return
        }
        let path = url
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let size = try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int,
           size > 200_000,
           let existing = try? String(contentsOf: path, encoding: .utf8) {
            let kept = existing.split(separator: "\n").suffix(500).joined(separator: "\n") + "\n"
            try? kept.write(to: path, atomically: true, encoding: .utf8)
        }

        if let handle = try? FileHandle(forWritingTo: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: path)
        }
    }
}
