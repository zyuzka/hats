import Foundation

enum SessionStageLimits {
    enum Found: Equatable {
        case absent
        case episodes([LimitEpisode])
        case unreadable(String)

        var hasEpisodes: Bool {
            guard case .episodes(let episodes) = self else { return false }

            return !episodes.isEmpty
        }

        func getTrouble() -> String? {
            guard case .unreadable(let trouble) = self else { return nil }

            return trouble
        }

        func getEpisodes() -> [LimitEpisode] {
            guard case .episodes(let episodes) = self else { return [] }

            return episodes
        }
    }

    static let percentRange = 0.0...100.0

    static func findEpisodes(in data: Data) -> Found {
        guard let envelope = try? JSONDecoder().decode(LimitsEnvelope.self, from: data) else {
            return .unreadable("its limits are not readable")
        }
        guard let limits = envelope.limits else { return .absent }
        var episodes: [LimitEpisode] = []
        for limit in StageLimit.allCases {
            guard let current = limits.getEpisode(limit) else { continue }
            let chain = [current.previous, current].compactMap { $0 }
            for fields in chain {
                guard let episode = createEpisode(fields, limit: limit) else {
                    return .unreadable("its \(limit.rawValue) limit is not readable")
                }
                episodes.append(episode)
            }
        }

        return .episodes(episodes)
    }

    private static func createEpisode(_ fields: EpisodeFields, limit: StageLimit) -> LimitEpisode? {
        guard let resetsAt = UsageReading.date(from: fields.resetsAt),
              percentRange.contains(fields.percent),
              LimitThresholds.isAUsablePair(warn: fields.warnPercent, save: fields.savePercent)
        else { return nil }
        var events: [LimitEvent] = []
        for (stage, event) in [(LimitStage.warned, fields.warned), (LimitStage.asked, fields.asked)] {
            guard let event else { continue }
            guard let made = createEvent(event, stage: stage) else { return nil }
            events.append(made)
        }

        return LimitEpisode(
            limit: limit,
            resetsAt: resetsAt,
            percent: fields.percent,
            warnPercent: fields.warnPercent,
            savePercent: fields.savePercent,
            events: events
        )
    }

    private static func createEvent(_ fields: EventFields, stage: LimitStage) -> LimitEvent? {
        guard let at = UsageReading.date(from: fields.at),
              percentRange.contains(fields.percent),
              !fields.worn.isEmpty,
              let reason = LimitReason(rawValue: fields.reason)
        else { return nil }

        return LimitEvent(stage: stage, at: at, percent: fields.percent, worn: fields.worn, reason: reason)
    }
}

private struct LimitsEnvelope: Decodable {
    let limits: LimitsFields?
}

private struct LimitsFields: Decodable {
    let fiveHour: EpisodeFields?
    let sevenDay: EpisodeFields?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    func getEpisode(_ limit: StageLimit) -> EpisodeFields? {
        switch limit {
        case .fiveHour: return fiveHour
        case .sevenDay: return sevenDay
        }
    }
}

private final class EpisodeFields: Decodable {
    let resetsAt: String
    let percent: Double
    let warnPercent: Int?
    let savePercent: Int?
    let warned: EventFields?
    let asked: EventFields?
    let previous: EpisodeFields?

    enum CodingKeys: String, CodingKey {
        case resetsAt = "resets_at"
        case percent
        case warnPercent = "warn_percent"
        case savePercent = "save_percent"
        case warned
        case asked
        case previous
    }
}

private struct EventFields: Decodable {
    let at: String
    let percent: Double
    let worn: String
    let reason: String
}
