import Foundation

enum UsageLimit: String, Codable, Equatable {
    case session
    case weekly

    var displayName: String {
        switch self {
        case .session: return "5-hour limit"
        case .weekly: return "weekly limit"
        }
    }
}

struct AutoSwitchPolicy: Codable, Equatable {
    var isOn = false
    var sessionThresholdPercent: Int? = 90
    var weeklyThresholdPercent: Int? = 95
    var order: [String] = []
    var notifies = true

    var wantsNotifications: Bool { isOn && notifies }

    func hasJustBeenTurnedOn(from previous: AutoSwitchPolicy) -> Bool { isOn && !previous.isOn }

    func crossedLimit(in reading: UsageReading) -> (UsageLimit, UsageWindow)? {
        if let threshold = sessionThresholdPercent, let window = reading.session,
           window.percent >= threshold {
            return (.session, window)
        }
        if let threshold = weeklyThresholdPercent, let window = reading.weekly,
           window.percent >= threshold {
            return (.weekly, window)
        }
        return nil
    }

    func room(for id: String, readings: [String: UsageReading]) -> HatRoom {
        guard let reading = readings[id] else { return .unknown }
        return crossedLimit(in: reading) == nil ? .free : .spent
    }

    func nextHat(after wearing: String?,
                 among eligible: [String],
                 readings: [String: UsageReading]) -> String? {
        let shown = candidates(after: wearing, among: eligible)
        return shown.first { room(for: $0, readings: readings) == .free }
            ?? shown.first { room(for: $0, readings: readings) == .unknown }
    }
}

enum AutoSwitchCause: String, Codable, Equatable {
    case reachedALimit
    case usageCouldNotBeRead
}

struct LastLiveWindow: Equatable {
    let limit: UsageLimit
    let percent: Int
}

struct AutoSwitchRecord: Codable, Equatable {
    let firedAt: Date
    let from: String
    let to: String
    let limit: UsageLimit?
    let resetsAt: Date?
    var cause: AutoSwitchCause?
    var seenInPopover = false

    var journalReason: String {
        switch cause {
        case .usageCouldNotBeRead: return AutoSwitchCause.usageCouldNotBeRead.rawValue
        case .reachedALimit, .none: return limit?.rawValue ?? "-"
        }
    }
}

enum HatRoom: Equatable {
    case free
    case unknown
    case spent
}

enum AutoSwitchHold: String, Equatable {
    case off
    case noHatOn
    case noReading
    case underTheThresholds
    case blindAndNear
    case blindAndFar
    case blindTargetSpent

    var isWorthAJournalLine: Bool { self != .off }
}

enum AutoSwitchDecision: Equatable {
    case hold
    case nowhereToGo(UsageLimit?)
    case fire(to: String, limit: UsageLimit, resetsAt: Date?)
    case fireBlind(to: String, lastSeen: LastLiveWindow)
}

extension AutoSwitchPolicy {
    func decide(
        reading: UsageReading?,
        wearing: String?,
        eligible: [String],
        readings: [String: UsageReading],
        blindness: UsageBlindness = UsageBlindness(),
        at now: Date = Date()
    ) -> AutoSwitchDecision {
        guard isOn, let reading else { return .hold }
        if let (limit, window) = crossedLimit(in: reading) {
            guard let next = nextHat(after: wearing, among: eligible, readings: readings) else {
                return .nowhereToGo(limit)
            }
            return .fire(to: next, limit: limit, resetsAt: window.resetsAt)
        }
        guard blindness.isBlindEnoughToSwitch,
              let near = nearestWindow(in: reading, at: now)
        else { return .hold }
        let seen = candidatesReadInThisPoll(
            after: wearing,
            among: eligible,
            readings: readings,
            fresh: blindness.fresh
        )
        guard !seen.isEmpty else { return .nowhereToGo(nil) }
        guard let next = blindTarget(
            after: wearing,
            among: eligible,
            readings: readings,
            fresh: blindness.fresh,
            at: now
        ) else { return .hold }

        return .fireBlind(to: next, lastSeen: near)
    }
}
