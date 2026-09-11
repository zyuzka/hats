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
        }
    }
}

struct AutoSwitchWorld: Equatable {
    var readings: [String: UsageReading] = [:]
    var wearing: String?
    var eligible: [String] = []
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
            readings: world.readings
        )
        switch decision {
        case .hold:
            return .hold
        case .nowhereToGo:
            return AutoSwitchOutcome(decision: decision, record: nil, notifies: false)
        case .fire(let id, let limit, let resetsAt):
            guard let from = wearing else { return .hold }
            let record = AutoSwitchRecord(
                firedAt: now, from: from, to: id, limit: limit, resetsAt: resetsAt
            )
            return AutoSwitchOutcome(decision: decision, record: record, notifies: policy.notifies)
        }
    }

    static func reasonForHolding(policy: AutoSwitchPolicy, world: AutoSwitchWorld) -> AutoSwitchHold? {
        guard policy.isOn else { return .off }
        guard let wearing = world.wearing else { return .noHatOn }
        guard let reading = world.readings[wearing] else { return .noReading }
        guard policy.crossedLimit(in: reading) == nil else { return nil }

        return .underTheThresholds
    }

    static func eligible(in rows: [HatRowState]) -> [String] {
        rows.filter(\.isSwitchable).map(\.id)
    }

    static func notice(for outcome: AutoSwitchOutcome, title: (String) -> String) -> (String, String)? {
        guard outcome.notifies else { return nil }
        switch outcome.decision {
        case .hold, .nowhereToGo:
            return nil
        case .fire(let id, let limit, _):
            guard let record = outcome.record else { return nil }
            return ("Switched to \(title(id))",
                    "\(title(record.from)) reached its \(limit.displayName).")
        }
    }
}
