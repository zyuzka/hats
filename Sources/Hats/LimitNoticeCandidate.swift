import Foundation

struct LimitNoticeCandidate {
    let limit: StageLimit
    let resetsAt: Date
    let savePercent: Int?
    let event: LimitEvent

    private static func findEarlyPace(of event: LimitEvent) -> (target: Int, minutes: Int)? {
        guard event.early, let target = event.target, let minutes = event.minutesToSave else { return nil }

        return (target, minutes)
    }

    static func getBody(of candidate: LimitNoticeCandidate) -> String {
        let event = candidate.event
        if let pace = findEarlyPace(of: event) {
            return HatsCopy.getEarlyLimitNoticeBody(reason: event.reason, target: pace.target, minutes: pace.minutes)
        }

        return HatsCopy.getLimitNoticeBody(stage: event.stage, reason: event.reason, save: candidate.savePercent)
    }

    static func getAlertDetails(of candidate: LimitNoticeCandidate, episode: Date) -> [String: String] {
        let event = candidate.event
        let pace = findEarlyPace(of: event)
        let eventTime = ISO8601DateFormatter()
        eventTime.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        var details = [
            "hat": event.worn,
            "limit": candidate.limit.rawValue,
            "stage": event.stage.rawValue,
            "percent": String(Int(event.percent.rounded(.down))),
            "episode": ISO8601DateFormatter().string(from: episode),
            "at": eventTime.string(from: event.at),
            "early": pace == nil ? "0" : "1",
        ]
        if let target = event.target { details["target"] = String(target) }
        if let lead = event.leadSeconds { details["lead_seconds"] = String(lead) }
        if let pace { details["minutes_to_save"] = String(pace.minutes) }

        return details
    }

    static func findCandidates(in stages: [SessionStage]) -> [LimitNoticeCandidate] {
        let all = stages.flatMap { stage in
            stage.limitEpisodes.flatMap { episode in
                episode.events.map {
                    LimitNoticeCandidate(
                        limit: episode.limit,
                        resetsAt: episode.resetsAt,
                        savePercent: episode.savePercent,
                        event: $0
                    )
                }
            }
        }

        return all.enumerated()
            .sorted {
                let left = getOrder($0.element, offset: $0.offset)
                return left.lexicographicallyPrecedes(getOrder($1.element, offset: $1.offset))
            }
            .map(\.element)
    }

    private static func getOrder(_ candidate: LimitNoticeCandidate, offset: Int) -> [Double] {
        let stage = LimitStage.allCases.firstIndex(of: candidate.event.stage) ?? 0

        return [
            LimitThresholdNotices.getMilliseconds(of: candidate.event.at),
            Double(stage),
            Double(offset),
        ]
    }
}
