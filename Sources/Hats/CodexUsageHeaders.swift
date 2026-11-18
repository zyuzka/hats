import Foundation

struct CodexUsageWindow: Equatable {
    let minutes: Int
    let percent: Int
    let resetsAt: Date?
}

struct CodexUsageReading: Equatable {
    let windows: [CodexUsageWindow]
    let plan: String?

    func window(minutes: Int) -> CodexUsageWindow? { windows.first { $0.minutes == minutes } }

    var journalLine: String {
        windows.map { "\($0.minutes)m=\($0.percent)%" }.joined(separator: ",")
    }
}

enum CodexUsageHeaders {
    static let families = ["primary", "secondary"]

    static func reading(in header: (String) -> String?) -> CodexUsageReading? {
        let windows = families.compactMap { window(named: $0, in: header) }
        guard !windows.isEmpty else { return nil }
        return CodexUsageReading(windows: windows, plan: header("x-codex-plan-type"))
    }

    static func journalEntry(hatID: String, reading: CodexUsageReading) -> [String: String] {
        ["hat": String(hatID.prefix(8)), "windows": reading.journalLine, "plan": reading.plan ?? "-"]
    }

    static func window(named family: String, in header: (String) -> String?) -> CodexUsageWindow? {
        let prefix = "x-codex-\(family)-"
        guard let minutes = number(header(prefix + "window-minutes")), minutes > 0,
              let used = header(prefix + "used-percent").flatMap(percent) else { return nil }
        let reset = number(header(prefix + "reset-at")).map { Date(timeIntervalSince1970: TimeInterval($0)) }

        return CodexUsageWindow(minutes: minutes, percent: used, resetsAt: reset)
    }

    static func number(_ text: String?) -> Int? {
        guard let text else { return nil }
        return Int(text.trimmingCharacters(in: .whitespaces))
    }

    static func percent(_ text: String) -> Int? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite, value >= 0 else {
            return nil
        }
        return Int(value.rounded())
    }
}
