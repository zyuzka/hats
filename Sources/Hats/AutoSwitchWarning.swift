import Foundation

enum AutoSwitchWarning: Equatable {
    case willSwitchWhenItCan
    case nowhereFreshToGo
    case everyOtherHatIsSpent

    static func of(
        decision: AutoSwitchDecision,
        holding: AutoSwitchHold?,
        blindness: UsageBlindness
    ) -> AutoSwitchWarning? {
        guard blindness.landedAPoll else { return nil }
        switch decision {
        case .fire, .fireBlind:
            return nil
        case .nowhereToGo(let limit):
            return limit == nil ? .nowhereFreshToGo : nil
        case .hold:
            break
        }
        switch holding {
        case .blindAndNear:
            return .willSwitchWhenItCan
        case .blindTargetSpent:
            return .everyOtherHatIsSpent
        case .off, .noHatOn, .noReading, .underTheThresholds, .blindAndFar, .none:
            return nil
        }
    }

    func text(hat: String) -> (String, String) {
        switch self {
        case .willSwitchWhenItCan: return HatsCopy.cannotReadTheUsage(of: hat)
        case .nowhereFreshToGo: return HatsCopy.cannotReadTheUsageAndHasNowhereToGo(of: hat)
        case .everyOtherHatIsSpent: return HatsCopy.cannotReadTheUsageAndTheOthersAreSpent(of: hat)
        }
    }
}
