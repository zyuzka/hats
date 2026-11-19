import Foundation

struct CodexCompactLine: Equatable {
    let name: String
    let details: [String: String]

    var outcome: String {
        let state = [
            "codexCompact.written": "codexCompact.unchanged",
            "codexCompact.removed": "codexCompact.notWritten",
        ]

        return (state[name] ?? name) + (details["value"].map { "=\($0)" } ?? "")
    }
}

final class CodexCompactLimitSync {
    static let folderName = "codex-windows"
    static let lookEvery: TimeInterval = 10

    typealias Log = (String, [String: String]) -> Void

    private let folder: URL
    private let config: CodexConfigFile
    private let log: Log
    private let now: () -> Date
    private var lastDecision: CodexCompactDecision?
    private var lastOutcome: String?
    private var lastLook: (savePercent: Int?, at: Date)?
    private var lastFailure = NoteOnChange()

    init(
        root: URL = StateDirectory.url,
        config: URL = CodexHome.real.config,
        log: @escaping Log = Journal.log,
        now: @escaping () -> Date = Date.init
    ) {
        folder = root.appendingPathComponent(Self.folderName)
        var file = CodexConfigFile(url: config)
        file.journalName = "codexCompact.config"
        self.config = file
        self.log = log
        self.now = now
    }

    func sync(savePercent: Int?) {
        let at = now()
        if let lastLook, lastLook.savePercent == savePercent, at.timeIntervalSince(lastLook.at) < Self.lookEvery {
            return
        }
        lastLook = (savePercent, at)
        let decision = CodexCompactLimit.decide(
            savePercent: savePercent,
            window: CodexCompactLimit.smallestWindow(in: folder, now: at)
        )
        do {
            let line = try apply(decision, savePercent: savePercent)
            lastFailure.clear()
            if isWorthALine(decision, line) { log(line.name, line.details) }
            lastDecision = decision
            lastOutcome = line.outcome
        } catch {
            guard lastFailure.shouldWrite(error.localizedDescription) else { return }
            log("codexCompact.failed", ["reason": error.localizedDescription])
        }
    }

    private func isWorthALine(_ decision: CodexCompactDecision, _ line: CodexCompactLine) -> Bool {
        guard decision == lastDecision else { return true }
        if line.name == "codexCompact.written" || line.name == "codexCompact.removed" { return true }

        return line.outcome != lastOutcome
    }

    private func apply(_ decision: CodexCompactDecision, savePercent: Int?) throws -> CodexCompactLine {
        switch decision {
        case .windowUnknown:
            return try remove(reason: "windowUnknown", [:])
        case .write(let tokens, let window):
            let value = CodexCompactLimit.value(tokens)
            let outcome = try config.apply {
                CodexConfigText.setting(value, in: $0, key: CodexCompactLimit.key, isOurs: CodexCompactLimit.isOurs)
            }
            return line(outcome, [
                "tokens": String(tokens),
                "window": String(window),
                "savePercent": savePercent.map(String.init) ?? "off",
            ])
        case .saveOff:
            return try remove(reason: "saveOff", [:])
        case .smallWindow(let tokens, let window):
            return try remove(reason: "smallWindow", [
                "tokens": String(tokens),
                "window": String(window),
                "lowest": String(CodexCompactLimit.lowest),
            ])
        }
    }

    private func remove(reason: String, _ details: [String: String]) throws -> CodexCompactLine {
        let isOurs = CodexCompactLimit.isOurs
        let outcome = try config.apply {
            CodexConfigText.removing(in: $0, key: CodexCompactLimit.key, isOurs: isOurs, mayEmpty: false)
        }
        var all = details
        all["reason"] = reason
        switch outcome {
        case .written, .removed:
            return CodexCompactLine(name: "codexCompact.removed", details: all)
        case .unchanged:
            return CodexCompactLine(name: "codexCompact.notWritten", details: all)
        case .foreign, .unsupported:
            return line(outcome, all)
        }
    }

    private func line(_ outcome: CodexConfigOutcome, _ details: [String: String]) -> CodexCompactLine {
        var all = details
        switch outcome {
        case .written:
            return CodexCompactLine(name: "codexCompact.written", details: all)
        case .unchanged:
            return CodexCompactLine(name: "codexCompact.unchanged", details: all)
        case .removed:
            return CodexCompactLine(name: "codexCompact.removed", details: all)
        case .foreign(let value):
            all["value"] = value
            return CodexCompactLine(name: "codexCompact.foreign", details: all)
        case .unsupported:
            return CodexCompactLine(name: "codexCompact.unsupported", details: all)
        }
    }
}
