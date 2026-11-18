import Foundation

struct ProviderAverage: Equatable {
    let withoutVacation: Int?
    let withVacation: Int?

    static func of(_ entries: [(percent: Int, isOnVacation: Bool)]) -> ProviderAverage {
        let working = entries.filter { !$0.isOnVacation }.map(\.percent)
        let hasVacation = entries.contains { $0.isOnVacation }

        return ProviderAverage(
            withoutVacation: rounded(working),
            withVacation: hasVacation ? rounded(entries.map(\.percent)) : nil
        )
    }

    static func rounded(_ percents: [Int]) -> Int? {
        guard !percents.isEmpty else { return nil }
        let sum = percents.reduce(0, +)

        return (2 * sum + percents.count) / (2 * percents.count)
    }
}

struct ProviderSummary: Equatable {
    let session: ProviderAverage
    let week: ProviderAverage

    static func of(_ rows: [HatRowState], now: Date) -> ProviderSummary {
        let sessions = rows.compactMap { row in
            row.usage?.session.map { (percent: shown($0, now: now), isOnVacation: row.isOnVacation) }
        }
        let weeks = rows.compactMap { row in
            row.weekSighting.map { (percent: shown($0.window, now: now), isOnVacation: row.isOnVacation) }
        }

        return ProviderSummary(session: .of(sessions), week: .of(weeks))
    }

    private static func shown(_ window: UsageWindow, now: Date) -> Int {
        if let resetsAt = window.resetsAt, resetsAt <= now { return 0 }

        return min(max(window.percent, 0), 100)
    }
}
