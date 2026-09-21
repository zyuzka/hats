import Foundation

enum AutoSwitchCall: Equatable {
    case aPollLanded
    case thePopoverOpened
    case theToggleChanged
}

struct UsageBlindness: Equatable {
    static let missesBeforeAWarning = 1
    static let missesBeforeASwitch = 2

    var missedPolls = 0
    var hasReadTheWornHatSinceItWentOn = false
    var fresh: Set<String> = []
    var landedAPoll = false

    var isBlind: Bool {
        hasReadTheWornHatSinceItWentOn && missedPolls >= Self.missesBeforeAWarning
    }

    var isBlindEnoughToSwitch: Bool {
        landedAPoll && hasReadTheWornHatSinceItWentOn && missedPolls >= Self.missesBeforeASwitch
    }

    static func of(_ missed: MissedPolls, fresh: Set<String>, from call: AutoSwitchCall) -> UsageBlindness {
        UsageBlindness(
            missedPolls: missed.count,
            hasReadTheWornHatSinceItWentOn: missed.hasReadTheWornHatSinceItWentOn,
            fresh: fresh,
            landedAPoll: call == .aPollLanded
        )
    }
}

extension AutoSwitchWorld {
    static func of(
        snapshot: HatsSnapshot,
        readings: [String: UsageReading],
        missed: MissedPolls,
        fresh: Set<String>,
        from call: AutoSwitchCall
    ) -> AutoSwitchWorld {
        AutoSwitchWorld(
            readings: readings,
            wearing: snapshot.wearing?.id,
            eligible: AutoSwitchEngine.eligible(in: snapshot.rows),
            blindness: UsageBlindness.of(missed, fresh: fresh, from: call)
        )
    }
}

extension AutoSwitchPolicy {
    static let marginOfANearThreshold = 10

    static func nearFrom(_ threshold: Int) -> Int { max(0, threshold - marginOfANearThreshold) }

    private func nearWindow(
        _ limit: UsageLimit,
        _ window: UsageWindow?,
        _ threshold: Int?,
        _ now: Date
    ) -> (window: LastLiveWindow, points: Int)? {
        guard let threshold, let window, window.percent >= Self.nearFrom(threshold) else { return nil }
        guard window.resetsAt.map({ $0 > now }) ?? true else { return nil }

        return (LastLiveWindow(limit: limit, percent: window.percent), threshold - window.percent)
    }

    func nearestWindow(in reading: UsageReading, at now: Date = Date()) -> LastLiveWindow? {
        let session = nearWindow(.session, reading.session, sessionThresholdPercent, now)
        let weekly = nearWindow(.weekly, reading.weekly, weeklyThresholdPercent, now)
        guard let session else { return weekly?.window }
        guard let weekly else { return session.window }

        return weekly.points < session.points ? weekly.window : session.window
    }

    func isNearAThreshold(_ reading: UsageReading, at now: Date = Date()) -> Bool {
        nearestWindow(in: reading, at: now) != nil
    }

    func hasTheSessionWindowItsThresholdNeeds(_ reading: UsageReading) -> Bool {
        sessionThresholdPercent == nil || reading.session != nil
    }

    func hasRoomToSpare(_ id: String, readings: [String: UsageReading], at now: Date = Date()) -> Bool {
        guard room(for: id, readings: readings) == .free, let reading = readings[id] else { return false }
        guard hasTheSessionWindowItsThresholdNeeds(reading) else { return false }

        return !isNearAThreshold(reading, at: now)
    }

    func candidates(after wearing: String?, among eligible: [String]) -> [String] {
        let shown = order + eligible.filter { !order.contains($0) }

        return shown.filter { $0 != wearing && eligible.contains($0) }
    }

    func candidatesReadInThisPoll(
        after wearing: String?,
        among eligible: [String],
        readings: [String: UsageReading],
        fresh: Set<String>
    ) -> [String] {
        candidates(after: wearing, among: eligible)
            .filter { fresh.contains($0) && readings[$0] != nil }
    }

    func blindTarget(
        after wearing: String?,
        among eligible: [String],
        readings: [String: UsageReading],
        fresh: Set<String>,
        at now: Date = Date()
    ) -> String? {
        candidatesReadInThisPoll(after: wearing, among: eligible, readings: readings, fresh: fresh)
            .first { hasRoomToSpare($0, readings: readings, at: now) }
    }
}
