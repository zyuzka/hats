import Foundation

enum RateLimitHeaders {
    static let sessionUtilization = "anthropic-ratelimit-unified-5h-utilization"
    static let sessionReset = "anthropic-ratelimit-unified-5h-reset"
    static let weeklyUtilization = "anthropic-ratelimit-unified-7d-utilization"
    static let weeklyReset = "anthropic-ratelimit-unified-7d-reset"

    static func findReading(in header: (String) -> String?) -> UsageReading? {
        let reading = UsageReading(
            session: findWindow(utilization: header(sessionUtilization), reset: header(sessionReset)),
            weekly: findWindow(utilization: header(weeklyUtilization), reset: header(weeklyReset))
        )

        return reading.hasAnyWindow ? reading : nil
    }

    private static func findWindow(utilization: String?, reset: String?) -> UsageWindow? {
        guard let text = utilization, let fraction = Double(text), fraction.isFinite else { return nil }
        let resetsAt = reset.flatMap(TimeInterval.init).flatMap { seconds in
            seconds.isFinite ? Date(timeIntervalSince1970: seconds) : nil
        }

        return UsageWindow(
            used: getPercent(of: text, fraction: fraction),
            limit: 100,
            resetsAt: resetsAt
        )
    }

    private static func getPercent(of text: String, fraction: Double) -> Int {
        let bounded = min(max(fraction, 0), 1)
        let posix = Locale(identifier: "en_US_POSIX")
        guard bounded == fraction,
              let exact = Decimal(string: text.trimmingCharacters(in: .whitespaces), locale: posix),
              abs(NSDecimalNumber(decimal: exact).doubleValue - fraction) < 1e-9
        else { return Int((bounded * 100).rounded()) }
        var scaled = exact * 100
        var whole = Decimal()
        NSDecimalRound(&whole, &scaled, 0, .plain)

        return NSDecimalNumber(decimal: whole).intValue
    }
}
