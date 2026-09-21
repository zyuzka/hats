import Foundation

enum PollSource: Equatable {
    case timer
    case outOfBand
}

struct MissedPolls: Equatable {
    static let periodsOfSilenceThatMeanTheAppSlept = 2.0

    private(set) var count = 0
    private(set) var hasReadTheWornHatSinceItWentOn = false
    private var wornHat: String?
    private var landedAt: Date?

    func settled(
        wearing: String?,
        fresh: Set<String>,
        from source: PollSource,
        every interval: TimeInterval,
        at now: Date
    ) -> MissedPolls {
        var next = self
        if wearing != wornHat {
            next.wornHat = wearing
            next.count = 0
            next.hasReadTheWornHatSinceItWentOn = false
        }
        let wasRead = wearing.map(fresh.contains) ?? false
        if wasRead { next.hasReadTheWornHatSinceItWentOn = true }
        guard source == .timer else { return next }
        let silence = landedAt.map { now.timeIntervalSince($0) } ?? 0
        next.landedAt = now
        guard wearing != nil, !wasRead,
              silence <= interval * Self.periodsOfSilenceThatMeanTheAppSlept
        else {
            next.count = 0
            return next
        }
        next.count += 1

        return next
    }

    mutating func forget() { count = 0 }
}
