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

struct FirstWarning: Equatable {
    let episode: Date
    let at: Date

    func getFields() -> [String: Any] {
        let eventTime = ISO8601DateFormatter()
        eventTime.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]

        return [
            "episode": HatUsageRecord.getStamp(episode),
            "at": eventTime.string(from: at),
        ]
    }
}

struct FirstWarned: Equatable {
    let fiveHour: FirstWarning?
    let sevenDay: FirstWarning?

    static func find(in stages: [SessionStage], worn: String?, fiveHour: Date?, sevenDay: Date?) -> FirstWarned {
        FirstWarned(
            fiveHour: find(.fiveHour, episode: fiveHour, worn: worn, in: stages),
            sevenDay: find(.sevenDay, episode: sevenDay, worn: worn, in: stages)
        )
    }

    private static func find(
        _ limit: StageLimit,
        episode: Date?,
        worn: String?,
        in stages: [SessionStage]
    ) -> FirstWarning? {
        guard let worn, let episode else { return nil }
        let earliest = stages
            .flatMap(\.limitEpisodes)
            .filter {
                $0.limit == limit
                    && abs($0.resetsAt.timeIntervalSince(episode)) < LimitThresholdNotices.episodeSpell
            }
            .flatMap(\.events)
            .filter { $0.stage == .warned && $0.worn == worn }
            .map(\.at)
            .min()

        return earliest.map { FirstWarning(episode: episode, at: $0) }
    }

    func getFields() -> [String: Any] {
        [
            "five_hour": fiveHour?.getFields() ?? NSNull(),
            "seven_day": sevenDay?.getFields() ?? NSNull(),
        ]
    }
}
