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
        let shown = order + eligible.filter { !order.contains($0) }
        let candidates = shown.filter { $0 != wearing && eligible.contains($0) }
        return candidates.first { room(for: $0, readings: readings) == .free }
            ?? candidates.first { room(for: $0, readings: readings) == .unknown }
    }
}

struct AutoSwitchRecord: Codable, Equatable {
    let firedAt: Date
    let from: String
    let to: String
    let limit: UsageLimit
    let resetsAt: Date?
    var seenInPopover = false
}

enum HatRoom: Equatable {
    case free
    case unknown
    case spent
}

enum AutoSwitchDecision: Equatable {
    case hold
    case nowhereToGo(UsageLimit)
    case fire(to: String, limit: UsageLimit, resetsAt: Date?)
}

extension AutoSwitchPolicy {
    func decide(
        reading: UsageReading?,
        wearing: String?,
        eligible: [String],
        readings: [String: UsageReading]
    ) -> AutoSwitchDecision {
        guard isOn else { return .hold }
        guard let reading, let (limit, window) = crossedLimit(in: reading) else { return .hold }
        guard let next = nextHat(after: wearing, among: eligible, readings: readings) else {
            return .nowhereToGo(limit)
        }
        return .fire(to: next, limit: limit, resetsAt: window.resetsAt)
    }
}
