import Foundation

enum UsageObservation {
    struct Change: Equatable {
        let id: String
        let reason: String?
        let previously: String?

        var journalEvent: String { reason == nil ? "usage.cleared" : "usage.trouble" }

        var details: [String: String] {
            var details = ["hat": String(id.prefix(8))]
            if let reason { details["reason"] = reason }
            if let previously { details["previously"] = previously }

            return details
        }
    }

    static func changes(
        from before: [String: UsageTrouble],
        to after: [String: UsageTrouble],
        polled ids: Set<String>
    ) -> [Change] {
        ids.sorted().compactMap { id in
            let was = before[id]
            let now = after[id]
            guard was != now else { return nil }

            return Change(id: id, reason: now?.journalLine, previously: was?.journalLine)
        }
    }
}
