import Foundation

struct PluginCommandLine: Equatable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let seconds: TimeInterval
}

enum PluginCommandEnd: Equatable {
    case exited(Int32)
    case signalled(Int32)
    case timedOut
    case notStarted(String)
}

struct PluginCommandOutcome: Equatable {
    let end: PluginCommandEnd
    var stdout = Data()
    var stderr = Data()
    var isTruncated = false

    var stdoutText: String? { String(data: stdout, encoding: .utf8) }

    var lastErrorLine: String? {
        (String(bytes: stderr, encoding: .utf8) ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }

    var trouble: String? {
        switch end {
        case .exited(0):
            return isTruncated ? "its answer was longer than Hats reads, so it was cut off" : nil
        case .exited(let code):
            return lastErrorLine.map { "exit code \(code): \($0)" } ?? "exit code \(code)"
        case .signalled(let signal):
            return "it was stopped by signal \(signal)"
        case .timedOut:
            return "timed out"
        case .notStarted(let reason):
            return "it could not start: \(reason)"
        }
    }
}
