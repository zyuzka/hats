import Foundation

enum AutoSwitchWarning: Equatable {
    case willSwitchWhenItCan
    case nowhereFreshToGo
    case everyOtherHatIsSpent
    case everyOtherHatIsSpentOrOnVacation([HatOnVacation])
    case unreadableAndOthersAreOnVacation([HatOnVacation])
    case nowhereToGoAtALimit(UsageLimit, AutoSwitchDeadEnd.StrandedBy)

    static func of(
        decision: AutoSwitchDecision,
        holding: AutoSwitchHold?,
        blindness: UsageBlindness,
        onVacation: [HatOnVacation]
    ) -> AutoSwitchWarning? {
        guard blindness.landedAPoll else { return nil }
        switch decision {
        case .fire, .fireBlind:
            return nil
        case .nowhereToGo(let deadEnd):
            return createWarning(at: deadEnd)
        case .hold:
            break
        }
        switch holding {
        case .blindAndNear:
            return .willSwitchWhenItCan
        case .blindTargetSpent:
            return onVacation.isEmpty ? .everyOtherHatIsSpent : .everyOtherHatIsSpentOrOnVacation(onVacation)
        case .blindAndOthersAreOnVacation:
            return .unreadableAndOthersAreOnVacation(onVacation)
        case .off, .noHatOn, .noReading, .underTheThresholds, .blindAndFar, .none:
            return nil
        }
    }

    private static func createWarning(at deadEnd: AutoSwitchDeadEnd) -> AutoSwitchWarning {
        switch deadEnd {
        case .noFreshReading: return .nowhereFreshToGo
        case .unreadableAndOthersAreOnVacation(let away): return .unreadableAndOthersAreOnVacation(away)
        case .atALimit(let limit, let by): return .nowhereToGoAtALimit(limit, by)
        }
    }

    static func isTheSameEpisode(_ one: AutoSwitchWarning?, as two: AutoSwitchWarning?) -> Bool {
        if case .unreadableAndOthersAreOnVacation(let first) = one,
           case .unreadableAndOthersAreOnVacation(let second) = two {
            return HatsCopy.getOthersOnVacation(first) == HatsCopy.getOthersOnVacation(second)
        }
        guard case .nowhereToGoAtALimit(let first, let firstBy) = one,
              case .nowhereToGoAtALimit(let second, let secondBy) = two
        else { return one == two }

        return first == second && firstBy.isTheSameReasonAs(secondBy)
    }

    var menuBarLabel: String {
        switch self {
        case .willSwitchWhenItCan,
             .nowhereFreshToGo,
             .everyOtherHatIsSpent,
             .everyOtherHatIsSpentOrOnVacation,
             .unreadableAndOthersAreOnVacation:
            return HatsCopy.theWornUsageCannotBeReadAloud
        case .nowhereToGoAtALimit(let limit, _):
            return HatsCopy.nowhereToGoAloud(limit: limit)
        }
    }

    func text(hat: String, now: Date, timeZone: TimeZone = .current) -> (String, String) {
        switch self {
        case .willSwitchWhenItCan: return HatsCopy.cannotReadTheUsage(of: hat)
        case .nowhereFreshToGo: return HatsCopy.cannotReadTheUsageAndHasNowhereToGo(of: hat)
        case .everyOtherHatIsSpent: return HatsCopy.cannotReadTheUsageAndTheOthersAreSpent(of: hat)
        case .everyOtherHatIsSpentOrOnVacation(let away):
            return HatsCopy.getUnreadableAndSpentOrOnVacation(of: hat, onVacation: away)
        case .unreadableAndOthersAreOnVacation(let away):
            return HatsCopy.getCannotReadTheUsageAndTheOthersAreOnVacation(of: hat, onVacation: away)
        case .nowhereToGoAtALimit(let limit, let by):
            return HatsCopy.nowhereToGo(
                of: hat,
                limit: limit,
                strandedBy: by,
                now: now,
                timeZone: timeZone
            )
        }
    }
}

struct WhatTheWearTookAway: Equatable {
    let warning: AutoSwitchWarning?
    let announced: AutoSwitchWarning?
    let pollsLanded: Int
    let wearing: String?

    func isStillTheWorldToPutBack(pollsLanded: Int, wearing: String?) -> Bool {
        guard self.pollsLanded == pollsLanded else { return false }

        return self.wearing == wearing
    }
}

struct AutoSwitchWarningChange: Equatable {
    let keeps: AutoSwitchWarning?
    let remembers: AutoSwitchWarning?
    let redraws: Bool
    let announces: Bool

    static func of(
        _ incoming: AutoSwitchWarning?,
        held: AutoSwitchWarning?,
        announced: AutoSwitchWarning?,
        notifies: Bool
    ) -> AutoSwitchWarningChange {
        let says = isWorthSaying(incoming, after: announced, notifies: notifies)

        return AutoSwitchWarningChange(
            keeps: incoming,
            remembers: remembered(incoming, announced: announced, saying: says),
            redraws: held != incoming,
            announces: says
        )
    }

    private static func isWorthSaying(
        _ incoming: AutoSwitchWarning?,
        after announced: AutoSwitchWarning?,
        notifies: Bool
    ) -> Bool {
        guard incoming != nil, notifies else { return false }

        return !AutoSwitchWarning.isTheSameEpisode(announced, as: incoming)
    }

    private static func remembered(
        _ incoming: AutoSwitchWarning?,
        announced: AutoSwitchWarning?,
        saying: Bool
    ) -> AutoSwitchWarning? {
        guard incoming != nil else { return nil }

        return saying ? incoming : announced
    }
}
