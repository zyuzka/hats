import Foundation

enum CodexCompactDecision: Equatable {
    case write(tokens: Int, window: Int)
    case saveOff
    case smallWindow(tokens: Int, window: Int)
    case windowUnknown
}

enum CodexCompactLimit {
    static let name = "model_auto_compact_token_limit"
    static let mark = "# set by Hats"
    static let lowest = 40_000
    static let windowRange = 1...100_000_000
    static let windowAge: TimeInterval = 7 * 24 * 3600

    static let key = CodexConfigKey(
        name: name,
        value: { $0.trimmingCharacters(in: .whitespaces) },
        line: { "\(name) = \($0)" }
    )

    static func decide(savePercent: Int?, window: Int?) -> CodexCompactDecision {
        guard let savePercent else { return .saveOff }
        guard let window else { return .windowUnknown }
        let tokens = window * savePercent / 100
        guard tokens > lowest else { return .smallWindow(tokens: tokens, window: window) }

        return .write(tokens: tokens, window: window)
    }

    static func value(_ tokens: Int) -> String { "\(tokens) \(mark)" }

    static func isOurs(_ value: String) -> Bool {
        guard let markAt = value.range(of: "#") else { return false }
        let number = value[..<markAt.lowerBound].trimmingCharacters(in: .whitespaces)
        let comment = value[markAt.upperBound...].trimmingCharacters(in: .whitespaces)

        return !number.isEmpty && number.allSatisfy(\.isASCIIDigit) && "# \(comment)" == mark
    }

    static func smallestWindow(in folder: URL, now: Date) -> Int? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []

        return names
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
            .compactMap { read(folder.appendingPathComponent($0)) }
            .filter { now.timeIntervalSince($0.at) <= windowAge }
            .map(\.window)
            .min()
    }

    private static func read(_ url: URL) -> (window: Int, at: Date)? {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              (values.fileSize ?? .max) <= 64 * 1024,
              let at = values.contentModificationDate,
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let window = object["window"] as? Int,
              windowRange.contains(window)
        else { return nil }

        return (window, at)
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
