import Darwin
import Foundation

enum SessionStageKind: String, Equatable {
    case warned
    case requested
    case saved
    case failed
    case interrupted
    case kept
    case cleared
}

struct SessionStage: Equatable {
    let session: String
    let cwd: String?
    let kind: SessionStageKind
    let warnRound: Int
    let saveRound: Int
    let percent: Int?
    let warnPercent: Int?
    let savePercent: Int?
    let at: Date
}

enum SessionStageRead: Equatable {
    case read(SessionStage)
    case skipped(String)
}

enum SessionStageFile {
    static let sessionPattern = "^[0-9A-Za-z_-]{1,128}$"

    static func getRecord(_ name: String, in folder: URL) -> SessionStageRead {
        let descriptor = open(folder.appendingPathComponent(name).path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            return .skipped(errno == ELOOP ? "it is a link" : String(cString: strerror(errno)))
        }
        defer { close(descriptor) }
        var facts = stat()
        guard fstat(descriptor, &facts) == 0 else { return .skipped(String(cString: strerror(errno))) }
        guard facts.st_mode & S_IFMT == S_IFREG else { return .skipped("it is not a regular file") }
        guard let data = SessionWindowFile.getBytesUpToTheCap(descriptor) else {
            return .skipped("it could not be read")
        }
        guard data.count <= SessionWindowFile.sizeCap else {
            return .skipped("it is larger than \(SessionWindowFile.sizeCap / 1024) KB")
        }

        return getRecord(parsing: data, name: name)
    }

    static func getRecord(parsing data: Data, name: String) -> SessionStageRead {
        guard let raw = try? JSONDecoder().decode(SessionStageFields.self, from: data) else {
            return .skipped("it is not a session stage record")
        }
        guard raw.session.range(of: sessionPattern, options: .regularExpression) != nil,
              name == raw.session + ".json"
        else { return .skipped("its name is not its session") }
        guard let kind = raw.stage.flatMap(SessionStageKind.init(rawValue:)) else {
            return .skipped("its stage is unknown")
        }
        guard let at = UsageReading.date(from: raw.at) else { return .skipped("at is not a time") }
        if let trouble = findTroubleWithTheNumbers(raw) { return .skipped(trouble) }

        return .read(SessionStage(
            session: raw.session,
            cwd: raw.cwd,
            kind: kind,
            warnRound: raw.warnRound,
            saveRound: raw.saveRound,
            percent: raw.percent,
            warnPercent: raw.warnPercent,
            savePercent: raw.savePercent,
            at: at
        ))
    }

    private static func findTroubleWithTheNumbers(_ raw: SessionStageFields) -> String? {
        guard raw.warnRound >= 0, raw.saveRound >= 0 else { return "a round is negative" }
        if let percent = raw.percent, !(0...100).contains(percent) { return "the percent is outside 0…100" }
        if let warn = raw.warnPercent, !ContextThresholds.warnRange.contains(warn) {
            return "warn_percent is outside \(getText(of: ContextThresholds.warnRange))"
        }
        if let save = raw.savePercent, !ContextThresholds.saveRange.contains(save) {
            return "save_percent is outside \(getText(of: ContextThresholds.saveRange))"
        }

        return nil
    }
}

private func getText(of range: ClosedRange<Int>) -> String {
    "\(range.lowerBound)…\(range.upperBound)"
}

private struct SessionStageFields: Decodable {
    let session: String
    let cwd: String?
    let stage: String?
    let warnRound: Int
    let saveRound: Int
    let percent: Int?
    let warnPercent: Int?
    let savePercent: Int?
    let afterSave: String?
    let reason: String?
    let marker: String?
    let at: String

    enum CodingKeys: String, CodingKey {
        case session
        case cwd
        case stage
        case warnRound = "warn_round"
        case saveRound = "save_round"
        case percent
        case warnPercent = "warn_percent"
        case savePercent = "save_percent"
        case afterSave = "after_save"
        case reason
        case marker
        case at
    }
}
