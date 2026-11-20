import Foundation

struct CodexWindowMark: Equatable {
    let session: String
    let percent: Int
    let event: String?
    let writtenAt: Date
    var endPercent: Int?

    var fillAfterTheTurn: Int { max(percent, endPercent ?? percent) }
}

struct CodexWindowScan: Equatable {
    var marks: [CodexWindowMark] = []
    var present: Set<String> = []
}

enum CodexContinue {
    static let endOfTurn = "Stop"
    static let idleFor: TimeInterval = 20
    static let freshFor: TimeInterval = 10 * 60
    static let largestFile = 64 * 1024
    static let stamps = ISO8601DateFormatter()

    static func scan(_ folder: URL, now: Date) -> CodexWindowScan {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var scan = CodexWindowScan()
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            let stem = url.deletingPathExtension().lastPathComponent
            guard isASessionID(stem) else { continue }
            scan.present.insert(stem)
            if let mark = read(url, session: stem, now: now) { scan.marks.append(mark) }
        }

        return scan
    }

    static func isUnchanged(_ mark: CodexWindowMark, in folder: URL, now: Date) -> Bool {
        read(folder.appendingPathComponent("\(mark.session).json"), session: mark.session, now: now) == mark
    }

    static func isFresh(_ mark: CodexWindowMark, now: Date) -> Bool {
        now.timeIntervalSince(mark.writtenAt) <= freshFor
    }

    static func isASessionID(_ text: String) -> Bool {
        (1...80).contains(text.count) && text.allSatisfy { ($0.isASCII && $0.isLetter) || $0.isASCIIDigit || $0 == "-" }
    }

    private static func read(_ url: URL, session: String, now: Date) -> CodexWindowMark? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              (values.fileSize ?? .max) <= largestFile,
              let modified = values.contentModificationDate,
              now.timeIntervalSince(modified) <= freshFor,
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["session"] as? String == session,
              let percent = object["percent"] as? Int
        else { return nil }
        let stamp = (object["written_at"] as? String).flatMap { stamps.date(from: $0) }

        return CodexWindowMark(
            session: session,
            percent: percent,
            event: object["event"] as? String,
            writtenAt: stamp ?? modified,
            endPercent: object["end_percent"] as? Int
        )
    }
}

struct CodexContinueMemory: Equatable {
    private var acted: [String: Date] = [:]
    private var handled: [String: Date] = [:]

    var remembered: Set<String> { Set(acted.keys).union(handled.keys) }

    mutating func due(_ scan: CodexWindowScan, warn: Int?, save: Int?, now: Date) -> [CodexWindowMark] {
        forgetTheGone(scan.present, now: now)
        guard let warn, let save else { return [] }
        for mark in scan.marks where mark.percent < warn {
            acted[mark.session] = nil
        }

        return scan.marks
            .filter { isDue($0, save: save, now: now) }
            .sorted { $0.writtenAt < $1.writtenAt }
    }

    mutating func due(_ marks: [CodexWindowMark], warn: Int?, save: Int?, now: Date) -> [CodexWindowMark] {
        due(CodexWindowScan(marks: marks, present: Set(marks.map(\.session))), warn: warn, save: save, now: now)
    }

    mutating func noteActed(_ mark: CodexWindowMark) {
        acted[mark.session] = mark.writtenAt
        handled[mark.session] = mark.writtenAt
    }

    mutating func noteHandled(_ mark: CodexWindowMark) {
        handled[mark.session] = mark.writtenAt
    }

    private mutating func forgetTheGone(_ present: Set<String>, now: Date) {
        let isKept: (String, Date) -> Bool = { session, at in
            present.contains(session) || now.timeIntervalSince(at) <= CodexContinue.freshFor
        }
        acted = acted.filter { isKept($0.key, $0.value) }
        handled = handled.filter { isKept($0.key, $0.value) }
    }

    private func isDue(_ mark: CodexWindowMark, save: Int, now: Date) -> Bool {
        let idle = now.timeIntervalSince(mark.writtenAt)
        let hasEndedATurnAboveSave = mark.event == CodexContinue.endOfTurn && mark.fillAfterTheTurn >= save
        let hasRestedLongEnough = idle >= CodexContinue.idleFor && idle <= CodexContinue.freshFor
        let isNew = acted[mark.session] == nil && handled[mark.session] != mark.writtenAt

        return hasEndedATurnAboveSave && hasRestedLongEnough && isNew
    }
}
