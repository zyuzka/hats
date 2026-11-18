import Foundation

enum CodexAutoSwitch {
    static func world(of rows: [HatRowState], at now: Date) -> AutoSwitchWorld {
        AutoSwitchWorld(
            readings: readings(of: rows, at: now),
            wearing: rows.first(where: \.isWearing)?.id,
            eligible: AutoSwitchEngine.eligible(in: rows),
            blocked: AutoSwitchEngine.blocked(in: rows),
            onVacation: AutoSwitchEngine.findOnVacation(in: rows),
            blindness: UsageBlindness()
        )
    }

    static func readings(of rows: [HatRowState], at now: Date) -> [String: UsageReading] {
        Dictionary(
            rows.compactMap { row in row.usage.map { (row.id, afterTheResets($0, at: now)) } },
            uniquingKeysWith: { _, last in last }
        )
    }

    static func outcome(policy: AutoSwitchPolicy, rows: [HatRowState], at now: Date) -> AutoSwitchOutcome {
        AutoSwitchEngine.outcome(policy: policy, world: world(of: rows, at: now), now: now)
    }

    static func reasonForHolding(policy: AutoSwitchPolicy, rows: [HatRowState], at now: Date) -> AutoSwitchHold? {
        AutoSwitchEngine.reasonForHolding(policy: policy, world: world(of: rows, at: now), at: now)
    }

    static func nextHat(policy: AutoSwitchPolicy, rows: [HatRowState], at now: Date) -> String? {
        let world = world(of: rows, at: now)

        return policy.nextHat(after: world.wearing, among: world.eligible, readings: world.readings)
    }

    private static func afterTheResets(_ reading: UsageReading, at now: Date) -> UsageReading {
        UsageReading(
            session: reading.session.map { cleared($0, at: now) },
            weekly: reading.weekly.map { cleared($0, at: now) }
        )
    }

    private static func cleared(_ window: UsageWindow, at now: Date) -> UsageWindow {
        guard let resetsAt = window.resetsAt, resetsAt <= now else { return window }

        return UsageWindow(used: 0, limit: window.limit, resetsAt: resetsAt)
    }
}

extension CodexAutoSwitch {
    static func warning(for outcome: AutoSwitchOutcome, rows: [HatRowState]) -> AutoSwitchWarning? {
        AutoSwitchWarning.of(
            decision: outcome.decision,
            holding: nil,
            blindness: UsageBlindness(landedAPoll: true),
            onVacation: AutoSwitchEngine.findOnVacation(in: rows)
        )
    }
}

struct CodexAutoSwitchFailures: Equatable {
    private(set) var held: String?
    private var lastReason: String?

    private static func key(_ from: String, _ to: String) -> String { "\(from)>\(to)" }

    func allows(from: String, to: String) -> Bool { held != Self.key(from, to) }

    mutating func shouldWriteAFailure(from: String, to: String, reason: String) -> Bool {
        held = Self.key(from, to)
        defer { lastReason = reason }

        return lastReason != reason
    }

    mutating func aTimerPollCame() { held = nil }

    mutating func succeeded() {
        held = nil
        lastReason = nil
    }
}

extension AppSettings {
    mutating func forgetInTheSwitches(_ id: String) {
        autoSwitch.order.removeAll { $0 == id }
        codexAutoSwitch.order.removeAll { $0 == id }
        if let record = autoSwitchRecord, record.from == id || record.to == id { autoSwitchRecord = nil }
        if let record = codexAutoSwitchRecord, record.from == id || record.to == id { codexAutoSwitchRecord = nil }
    }
}
