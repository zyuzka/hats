import Foundation

enum WindowThresholdsSave: Equatable {
    case unchanged
    case written
    case failed(String)
}

struct WindowThresholdsFile {
    static let name = "window-thresholds.json"
    static let stageFolderName = "session-thresholds"

    let url: URL
    let stageFolder: URL
    private(set) var written: ContextThresholds?
    private(set) var writtenLimits: LimitThresholds?

    init(root: URL = StateDirectory.url) {
        url = root.appendingPathComponent(Self.name)
        stageFolder = root.appendingPathComponent(Self.stageFolderName)
    }

    static func getData(_ thresholds: ContextThresholds, limits: LimitThresholds, writtenAt: Date) throws -> Data {
        let fields: [String: Any] = [
            "warn_percent": thresholds.warnPercent ?? NSNull(),
            "save_percent": thresholds.savePercent ?? NSNull(),
            "after_save": thresholds.afterSave.rawValue,
            "drain": thresholds.drain,
            "drain_minutes": thresholds.drainMinutes,
            "limit_warn_percent": limits.warnPercent ?? NSNull(),
            "limit_save_percent": limits.savePercent ?? NSNull(),
            "written_at": ISO8601DateFormatter().string(from: writtenAt),
        ]

        return try JSONSerialization.data(
            withJSONObject: fields,
            options: [
                .prettyPrinted,
                .sortedKeys,
            ]
        )
    }

    mutating func setThresholds(
        _ thresholds: ContextThresholds,
        limits: LimitThresholds,
        at now: Date
    ) -> WindowThresholdsSave {
        let folderTrouble = SessionWindows.findTroubleMakingTheFolder(stageFolder)
            .map { WindowThresholdsSave.failed("\(Self.stageFolderName): \($0)") }
        guard isChanged(thresholds, limits: limits) || !FileManager.default.fileExists(atPath: url.path) else {
            return folderTrouble ?? .unchanged
        }
        do {
            try Self.getData(thresholds, limits: limits, writtenAt: now).write(to: url, options: .atomic)
            written = thresholds
            writtenLimits = limits
        } catch {
            return .failed(error.localizedDescription)
        }

        return folderTrouble ?? .written
    }

    private func isChanged(_ thresholds: ContextThresholds, limits: LimitThresholds) -> Bool {
        thresholds != written || limits != writtenLimits
    }
}
