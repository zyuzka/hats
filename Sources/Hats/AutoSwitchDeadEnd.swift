import Foundation

struct ShutOutHat: Equatable {
    let id: String
    let title: String
    let blocker: String
    let loginAction: String
}

enum AutoSwitchDeadEnd: Equatable {
    case noFreshReading
    case atALimit(UsageLimit, StrandedBy)

    enum StrandedBy: Equatable {
        case noOtherHat
        case othersNeedSigningIn(ShutOutHat, alsoShutOut: [ShutOutHat])
        case othersAreSpent(freesUpAt: Date?)

        func isTheSameReasonAs(_ other: StrandedBy) -> Bool {
            switch (self, other) {
            case (.othersAreSpent, .othersAreSpent):
                return true
            case (.othersNeedSigningIn(let mine, let alsoMine),
                  .othersNeedSigningIn(let theirs, let alsoTheirs)):
                return HatsCopy.signingIn(mine, alsoShutOut: alsoMine)
                    == HatsCopy.signingIn(theirs, alsoShutOut: alsoTheirs)
            default:
                return self == other
            }
        }

        var journalReason: String {
            switch self {
            case .noOtherHat: return "noOtherHat"
            case .othersNeedSigningIn: return "othersNeedSigningIn"
            case .othersAreSpent: return "othersAreSpent"
            }
        }
    }

    var journalLimit: String {
        guard case .atALimit(let limit, _) = self else {
            return AutoSwitchCause.usageCouldNotBeRead.rawValue
        }

        return limit.rawValue
    }

    var journalReason: String {
        guard case .atALimit(_, let by) = self else { return "-" }

        return by.journalReason
    }
}

struct NowhereToGoLine: Equatable {
    let limit: String
    let reason: String

    var key: String { "\(limit) \(reason)" }

    static func of(_ deadEnd: AutoSwitchDeadEnd) -> NowhereToGoLine {
        NowhereToGoLine(limit: deadEnd.journalLimit, reason: deadEnd.journalReason)
    }
}

extension AutoSwitchPolicy {
    func freesUpAt(_ reading: UsageReading) -> Date? {
        let resets = crossedLimits(in: reading).map { $0.1.resetsAt }
        guard !resets.isEmpty, !resets.contains(where: { $0 == nil }) else { return nil }

        return resets.compactMap { $0 }.max()
    }

    func whenSomethingFreesUp(
        wearing: String?,
        among hats: [String],
        readings: [String: UsageReading]
    ) -> Date? {
        let everyHat = [wearing].compactMap { $0 } + hats

        return everyHat.compactMap { readings[$0] }.compactMap { freesUpAt($0) }.min()
    }

    func strandedBy(
        after wearing: String?,
        among eligible: [String],
        blocked: [ShutOutHat],
        readings: [String: UsageReading]
    ) -> AutoSwitchDeadEnd.StrandedBy {
        let shutOut = blocked.filter { $0.id != wearing }
        let withRoom = shutOut.filter { room(for: $0.id, readings: readings) != .spent }
        if let first = withRoom.first {
            return .othersNeedSigningIn(first, alsoShutOut: Array(withRoom.dropFirst()))
        }
        let others = candidates(after: wearing, among: eligible)
        guard !others.isEmpty || !shutOut.isEmpty else { return .noOtherHat }
        let wornIsShutOutToo = blocked.contains { $0.id == wearing }
        let comesBack = wornIsShutOutToo ? nil : wearing

        return .othersAreSpent(
            freesUpAt: whenSomethingFreesUp(wearing: comesBack, among: others, readings: readings)
        )
    }
}
