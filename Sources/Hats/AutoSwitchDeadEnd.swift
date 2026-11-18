import Foundation

struct ShutOutHat: Equatable {
    let id: String
    let title: String
    let blocker: String
    let loginAction: String
}

struct HatOnVacation: Equatable {
    let id: String
    let title: String
}

enum AutoSwitchDeadEnd: Equatable {
    case noFreshReading
    case unreadableAndOthersAreOnVacation([HatOnVacation])
    case atALimit(UsageLimit, StrandedBy)

    static let othersAreOnVacationReason = "othersAreOnVacation"

    enum StrandedBy: Equatable {
        case noOtherHat
        case othersNeedSigningIn(ShutOutHat, alsoShutOut: [ShutOutHat])
        case othersAreSpent(freesUpAt: Date?)
        case othersAreSpentOrOnVacation(freesUpAt: Date?, onVacation: [HatOnVacation])
        case othersAreOnVacation([HatOnVacation])

        func isTheSameReasonAs(_ other: StrandedBy) -> Bool {
            switch (self, other) {
            case (.othersAreSpent, .othersAreSpent):
                return true
            case (.othersNeedSigningIn(let mine, let alsoMine),
                  .othersNeedSigningIn(let theirs, let alsoTheirs)):
                return HatsCopy.signingIn(mine, alsoShutOut: alsoMine)
                    == HatsCopy.signingIn(theirs, alsoShutOut: alsoTheirs)
            case (.othersAreSpentOrOnVacation(_, let mine), .othersAreSpentOrOnVacation(_, let theirs)):
                return HatsCopy.getAlsoOnVacation(mine) == HatsCopy.getAlsoOnVacation(theirs)
            case (.othersAreOnVacation(let mine), .othersAreOnVacation(let theirs)):
                return HatsCopy.getOthersOnVacation(mine) == HatsCopy.getOthersOnVacation(theirs)
            default:
                return self == other
            }
        }

        var journalReason: String {
            switch self {
            case .noOtherHat: return "noOtherHat"
            case .othersNeedSigningIn: return "othersNeedSigningIn"
            case .othersAreSpent, .othersAreSpentOrOnVacation: return "othersAreSpent"
            case .othersAreOnVacation: return AutoSwitchDeadEnd.othersAreOnVacationReason
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
        switch self {
        case .noFreshReading: return "-"
        case .unreadableAndOthersAreOnVacation: return Self.othersAreOnVacationReason
        case .atALimit(_, let by): return by.journalReason
        }
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
        readings: [String: UsageReading],
        at now: Date
    ) -> Date? {
        let everyHat = [wearing].compactMap { $0 } + hats

        return everyHat.compactMap { readings[$0] }
            .compactMap { freesUpAt($0) }
            .filter { $0 > now }
            .min()
    }

    func findEveryOtherHatOnVacation(
        after wearing: String?,
        among eligible: [String],
        blocked: [ShutOutHat],
        onVacation: [HatOnVacation]
    ) -> [HatOnVacation]? {
        guard !onVacation.isEmpty, candidates(after: wearing, among: eligible).isEmpty else { return nil }
        guard !blocked.contains(where: { $0.id != wearing }) else { return nil }

        return onVacation
    }

    func strandedBy(
        after wearing: String?,
        among eligible: [String],
        blocked: [ShutOutHat],
        onVacation: [HatOnVacation],
        readings: [String: UsageReading],
        at now: Date
    ) -> AutoSwitchDeadEnd.StrandedBy {
        let shutOut = blocked.filter { $0.id != wearing }
        let withRoom = shutOut.filter { room(for: $0.id, readings: readings) != .spent }
        if let first = withRoom.first {
            return .othersNeedSigningIn(first, alsoShutOut: Array(withRoom.dropFirst()))
        }
        let others = candidates(after: wearing, among: eligible)
        guard !others.isEmpty || !shutOut.isEmpty else {
            return onVacation.isEmpty ? .noOtherHat : .othersAreOnVacation(onVacation)
        }
        let wornIsShutOutToo = blocked.contains { $0.id == wearing }
        let comesBack = wornIsShutOutToo ? nil : wearing

        let freesUpAt = whenSomethingFreesUp(
            wearing: comesBack,
            among: others,
            readings: readings,
            at: now
        )
        guard !onVacation.isEmpty else { return .othersAreSpent(freesUpAt: freesUpAt) }

        return .othersAreSpentOrOnVacation(freesUpAt: freesUpAt, onVacation: onVacation)
    }
}
