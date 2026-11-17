import Foundation

struct LimitsEnvelope: Decodable {
    let limits: LimitsFields?
}

struct LimitsFields: Decodable {
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

final class EpisodeFields: Decodable {
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

struct EventFields: Decodable {
    let at: String
    let percent: Double
    let worn: String
    let reason: String
    let early: Bool?
    let minutesToSave: Int?
    let target: Int?
    let leadSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case at
        case percent
        case worn
        case reason
        case early
        case minutesToSave = "minutes_to_save"
        case target
        case leadSeconds = "lead_seconds"
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        at = try fields.decode(String.self, forKey: .at)
        percent = try fields.decode(Double.self, forKey: .percent)
        worn = try fields.decode(String.self, forKey: .worn)
        reason = try fields.decode(String.self, forKey: .reason)
        early = try? fields.decodeIfPresent(Bool.self, forKey: .early)
        minutesToSave = (try? fields.decodeIfPresent(Int.self, forKey: .minutesToSave)).flatMap { $0 >= 1 ? $0 : nil }
        let target = try? fields.decodeIfPresent(Int.self, forKey: .target)
        self.target = target.flatMap { LimitThresholds.range.contains($0) ? $0 : nil }
        leadSeconds = (try? fields.decodeIfPresent(Int.self, forKey: .leadSeconds)).flatMap { $0 >= 0 ? $0 : nil }
    }
}
