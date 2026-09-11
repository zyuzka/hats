import Foundation

enum SessionHorizon {
    static func line(soonestParkedAccessExpiry expiry: Date?, now: Date = Date()) -> String {
        let mechanism = "at its next token renewal"
        guard let expiry else { return mechanism }
        let remaining = expiry.timeIntervalSince(now)
        guard remaining > 0 else { return "\(mechanism), due now or overdue" }
        return "\(mechanism), by about \(UsageReading.clock(expiry)) (\(minutes(remaining)))"
    }

    static func minutes(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        if total < 60 { return "under a minute" }
        let mins = total / 60
        if mins < 60 { return "in \(mins) min" }
        let hours = mins / 60
        let rest = mins % 60
        return rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
    }
}

extension AccountStore {
    var soonestParkedAccessExpiry: Date? {
        guard let activeID else { return nil }
        let parked = accounts.filter { $0.id != activeID }.compactMap(\.accessExpiresAt)
        let now = Date()
        return parked.filter { $0 > now }.min() ?? parked.min()
    }
}
