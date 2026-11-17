import Foundation
import UserNotifications

private struct LimitNoticeCandidate {
    let limit: StageLimit
    let resetsAt: Date
    let savePercent: Int?
    let event: LimitEvent
}

final class LimitThresholdNotices {
    typealias Log = (String, [String: String]) -> Void

    static let keptFor: TimeInterval = 8 * 86400
    static let episodeSpell: TimeInterval = 3600

    private var file: LimitNoticesFile
    private let launchedAt: Date
    private let notify: (UNMutableNotificationContent) -> Void
    private let log: Log
    private let now: () -> Date
    private var entries: [LimitNoticeEntry]?

    var hatTitle: (String) -> String = { $0 }

    init(
        root: URL,
        launchedAt: Date,
        notify: @escaping (UNMutableNotificationContent) -> Void,
        log: @escaping Log,
        now: @escaping () -> Date
    ) {
        file = LimitNoticesFile(root: root, log: log)
        self.launchedAt = launchedAt
        self.notify = notify
        self.log = log
        self.now = now
    }

    func noteARead(_ read: SessionStagesRead) {
        let known = entries ?? file.getEntries()
        let oldest = now().addingTimeInterval(-Self.keptFor)
        var kept = known.filter { $0.toldAt >= oldest }
        var isChanged = kept.count != known.count
        let candidates = Self.findCandidates(in: read.stages).filter { $0.event.at >= oldest }
        for candidate in candidates {
            if Self.hasRefreshedTheRecord(of: candidate, in: &kept) {
                isChanged = true
                continue
            }
            let isKnown = kept.contains { Self.isTheSameEpisode($0, candidate) }
            guard isAfterTheLaunch(candidate), !isKnown else { continue }
            tell(candidate)
            kept.append(LimitNoticeEntry(
                hat: candidate.event.worn,
                limit: candidate.limit,
                stage: candidate.event.stage,
                resetsAt: candidate.resetsAt,
                toldAt: max(now(), candidate.event.at)
            ))
            isChanged = true
        }
        entries = kept
        if isChanged { file.setEntries(kept) }
    }

    private static func hasRefreshedTheRecord(
        of candidate: LimitNoticeCandidate,
        in kept: inout [LimitNoticeEntry]
    ) -> Bool {
        guard let index = kept.firstIndex(where: { isTheSameEpisode($0, candidate) }),
              kept[index].toldAt < candidate.event.at
        else { return false }
        let entry = kept[index]
        kept[index] = LimitNoticeEntry(
            hat: entry.hat,
            limit: entry.limit,
            stage: entry.stage,
            resetsAt: entry.resetsAt,
            toldAt: candidate.event.at
        )

        return true
    }

    private func isAfterTheLaunch(_ candidate: LimitNoticeCandidate) -> Bool {
        Self.getMilliseconds(of: candidate.event.at) >= Self.getMillisecondsDown(of: launchedAt)
    }

    private static func isTheSameEpisode(_ entry: LimitNoticeEntry, _ candidate: LimitNoticeCandidate) -> Bool {
        entry.hat == candidate.event.worn
            && entry.limit == candidate.limit
            && entry.stage == candidate.event.stage
            && abs(entry.resetsAt.timeIntervalSince(candidate.resetsAt)) < episodeSpell
    }

    private func tell(_ candidate: LimitNoticeCandidate) {
        let event = candidate.event
        let percent = Int(event.percent.rounded(.down))
        let title = HatsCopy.getLimitNoticeTitle(hat: hatTitle(event.worn), limit: candidate.limit, percent: percent)
        let body = HatsCopy.getLimitNoticeBody(stage: event.stage, reason: event.reason, save: candidate.savePercent)
        notify(Notifier.createContent(title: title, body: body))
        log("limit.alert", [
            "hat": event.worn,
            "limit": candidate.limit.rawValue,
            "stage": event.stage.rawValue,
            "percent": String(percent),
        ])
    }

    private static func findCandidates(in stages: [SessionStage]) -> [LimitNoticeCandidate] {
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
            getMilliseconds(of: candidate.event.at),
            Double(stage),
            Double(offset),
        ]
    }

    static func getMilliseconds(of date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded()
    }

    static func getMillisecondsDown(of date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded(.down)
    }
}
