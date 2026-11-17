import Foundation

struct HatUsageWindow: Equatable {
    let percent: Int
    let resetsAt: Date?

    init(_ window: UsageWindow) {
        percent = window.percent
        resetsAt = window.resetsAt
    }

    func getFields() -> [String: Any] {
        [
            "percent": percent,
            "resets_at": resetsAt.map(HatUsageRecord.getStamp) ?? NSNull(),
        ]
    }
}

struct SwitchCovers: Equatable {
    let fiveHour: Bool
    let sevenDay: Bool

    static func create(from snapshot: HatsSnapshot) -> SwitchCovers {
        let policy = snapshot.settings.autoSwitch
        let canSwitch = policy.isOn && snapshot.nextInLine != nil

        return SwitchCovers(
            fiveHour: canSwitch && policy.sessionThresholdPercent != nil,
            sevenDay: canSwitch && policy.weeklyThresholdPercent != nil
        )
    }

    func getFields() -> [String: Any] {
        [
            "five_hour": fiveHour,
            "seven_day": sevenDay,
        ]
    }
}

struct HatUsageRecord: Equatable {
    let worn: String?
    let fiveHour: HatUsageWindow?
    let weekly: HatUsageWindow?
    let measuredAt: Date?
    let hasAHatToSwitchTo: Bool
    let autoSwitchOn: Bool
    let credentialService: String?
    let switchCovers: SwitchCovers
    let aliveAt: Date?

    static func create(
        from snapshot: HatsSnapshot,
        readAt: [String: Date],
        liveSlot: String?,
        aliveAt: Date?
    ) -> HatUsageRecord {
        let worn = snapshot.wearing
        let reading = worn?.usage

        return HatUsageRecord(
            worn: worn?.id,
            fiveHour: reading?.session.map(HatUsageWindow.init),
            weekly: reading?.weekly.map(HatUsageWindow.init),
            measuredAt: reading == nil ? nil : worn.flatMap { readAt[$0.id] },
            hasAHatToSwitchTo: snapshot.nextInLine != nil,
            autoSwitchOn: snapshot.settings.autoSwitch.isOn,
            credentialService: worn == nil ? nil : liveSlot,
            switchCovers: SwitchCovers.create(from: snapshot),
            aliveAt: aliveAt
        )
    }

    static func create(from snapshot: HatsSnapshot, watch: AutoSwitchWatch) -> HatUsageRecord {
        create(
            from: snapshot,
            readAt: watch.readAt,
            liveSlot: watch.lastPoll?.liveSlot,
            aliveAt: watch.aliveAt
        )
    }

    static func getStamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    func getData(writtenAt: Date) throws -> Data {
        let fields: [String: Any] = [
            "worn": worn ?? NSNull(),
            "five_hour": fiveHour?.getFields() ?? NSNull(),
            "weekly": weekly?.getFields() ?? NSNull(),
            "measured_at": measuredAt.map(Self.getStamp) ?? NSNull(),
            "has_a_hat_to_switch_to": hasAHatToSwitchTo,
            "auto_switch_on": autoSwitchOn,
            "credential_service": credentialService ?? NSNull(),
            "switch_covers": switchCovers.getFields(),
            "alive_at": aliveAt.map(Self.getStamp) ?? NSNull(),
            "written_at": Self.getStamp(writtenAt),
        ]

        return try JSONSerialization.data(
            withJSONObject: fields,
            options: [
                .prettyPrinted,
                .sortedKeys,
            ]
        )
    }
}

enum HatUsageSave: Equatable {
    case unchanged
    case written
    case failed(String)
}

struct HatUsageFile {
    static let name = "hat-usage.json"

    let url: URL
    private(set) var written: HatUsageRecord?

    init(url: URL = StateDirectory.url.appendingPathComponent(HatUsageFile.name)) {
        self.url = url
    }

    mutating func setRecord(_ record: HatUsageRecord, at now: Date) -> HatUsageSave {
        guard record != written || !FileManager.default.fileExists(atPath: url.path) else { return .unchanged }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try record.getData(writtenAt: now).write(to: url, options: .atomic)
            written = record
            return .written
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
