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
