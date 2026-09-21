import Foundation

struct AutoSwitchOutcome: Equatable {
    let decision: AutoSwitchDecision
    let record: AutoSwitchRecord?
    let notifies: Bool

    static let hold = AutoSwitchOutcome(decision: .hold, record: nil, notifies: false)

    var wearsHat: String? {
        switch decision {
        case .hold, .nowhereToGo: return nil
        case .fire(let id, _, _): return id
        case .fireBlind(let id, _): return id
        }
    }
}

struct AutoSwitchWorld: Equatable {
    var readings: [String: UsageReading] = [:]
    var wearing: String?
    var eligible: [String] = []
    var blindness = UsageBlindness()
}

enum AutoSwitchEngine {
    static func outcome(
        policy: AutoSwitchPolicy,
        world: AutoSwitchWorld,
        now: Date
    ) -> AutoSwitchOutcome {
        let wearing = world.wearing
        let decision = policy.decide(
            reading: wearing.flatMap { world.readings[$0] },
            wearing: wearing,
            eligible: world.eligible,
            readings: world.readings,
            blindness: world.blindness,
            at: now
        )
        switch decision {
        case .hold:
            return .hold
        case .nowhereToGo:
            return AutoSwitchOutcome(decision: decision, record: nil, notifies: false)
        case .fire(let id, let limit, let resetsAt):
            guard let from = wearing else { return .hold }
            let record = AutoSwitchRecord(
                firedAt: now,
                from: from,
                to: id,
                limit: limit,
                resetsAt: resetsAt,
                cause: .reachedALimit
            )
            return AutoSwitchOutcome(decision: decision, record: record, notifies: policy.notifies)
        case .fireBlind(let id, let lastSeen):
            guard let from = wearing else { return .hold }
            let record = AutoSwitchRecord(
                firedAt: now,
                from: from,
                to: id,
                limit: lastSeen.limit,
                resetsAt: nil,
                cause: .usageCouldNotBeRead
            )
            return AutoSwitchOutcome(decision: decision, record: record, notifies: policy.notifies)
        }
    }

    static func reasonForHolding(
        policy: AutoSwitchPolicy,
        world: AutoSwitchWorld,
        at now: Date = Date()
    ) -> AutoSwitchHold? {
        guard policy.isOn else { return .off }
        guard let wearing = world.wearing else { return .noHatOn }
        guard let reading = world.readings[wearing] else { return .noReading }
        guard policy.crossedLimit(in: reading) == nil else { return nil }
        guard world.blindness.isBlind else { return .underTheThresholds }
        guard policy.isNearAThreshold(reading, at: now) else { return .blindAndFar }
        guard world.blindness.isBlindEnoughToSwitch else { return .blindAndNear }
        guard policy.blindTarget(
            after: wearing,
            among: world.eligible,
            readings: world.readings,
            fresh: world.blindness.fresh,
            at: now
        ) == nil else { return nil }

        return .blindTargetSpent
    }

    static func eligible(in rows: [HatRowState]) -> [String] {
        rows.filter(\.isSwitchable).map(\.id)
    }

    static func notice(
        for outcome: AutoSwitchOutcome,
        lastSeen age: TimeInterval? = nil,
        title: (String) -> String
    ) -> (String, String)? {
        guard outcome.notifies, let record = outcome.record else { return nil }
        switch outcome.decision {
        case .hold, .nowhereToGo:
            return nil
        case .fire(let id, let limit, _):
            return (HatsCopy.switched(to: title(id)),
                    "\(title(record.from)) reached its \(limit.displayName).")
        case .fireBlind(let id, let lastSeen):
            return (HatsCopy.switched(to: title(id)),
                    HatsCopy.switchedBecauseTheUsageWasUnreadable(
                        from: title(record.from), lastSeen: lastSeen, age: age
                    ))
        }
    }
}
