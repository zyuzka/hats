import Foundation

extension HatsCopy {
    static let noHandoverTheOthersAreOnVacation = "next: none, the others are on vacation"

    static let vacationMark = "on vacation"

    static let vacationExplained = "Auto-switch skips this hat. You can still put it on from the menu."

    static func getUnreadableAndSpentOrOnVacation(
        of hat: String,
        onVacation away: [HatOnVacation]
    ) -> (String, String) {
        ("Can't read usage",
         "Hats can't read \(hat)'s usage, and the other hats are spent; \(getAlsoOnVacation(away)).")
    }

    static func getCannotReadTheUsageAndTheOthersAreOnVacation(
        of hat: String,
        onVacation away: [HatOnVacation]
    ) -> (String, String) {
        ("Can't read usage",
         "Hats can't read \(hat)'s usage, and \(getOthersOnVacation(away))")
    }

    static func cannotReadTheUsage(of hat: String, strandedBy by: AutoSwitchDeadEnd.StrandedBy) -> (String, String) {
        switch by {
        case .noOtherHat:
            return ("Can't read usage", "Hats can't read \(hat)'s usage, and there is no other hat to switch to.")
        case .othersNeedSigningIn(let only, let also):
            return ("Can't read usage", "Hats can't read \(hat)'s usage, and \(signingIn(only, alsoShutOut: also)).")
        case .othersAreSpent:
            return cannotReadTheUsageAndTheOthersAreSpent(of: hat)
        case .othersAreSpentOrOnVacation(_, let away):
            return getUnreadableAndSpentOrOnVacation(of: hat, onVacation: away)
        case .othersAreOnVacation(let away):
            return getCannotReadTheUsageAndTheOthersAreOnVacation(of: hat, onVacation: away)
        }
    }

    static func getOthersOnVacation(_ hats: [HatOnVacation]) -> String {
        guard hats.count == 1, let only = hats.first else {
            return "the other hats are on vacation. End a vacation in Settings → Hats."
        }

        return "\(only.title) is on vacation. End the vacation in Settings → Hats."
    }

    static func getAlsoOnVacation(_ hats: [HatOnVacation]) -> String {
        let titles = hats.map(\.title)
        guard titles.count > 1 else { return "\(titles.joined()) is on vacation" }

        return "\(titles.dropLast().joined(separator: ", ")) and \(titles[titles.count - 1]) are on vacation"
    }
}
