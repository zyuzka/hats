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
        guard let fraction = utilization.flatMap(Double.init), fraction.isFinite else { return nil }
        let bounded = min(max(fraction, 0), 1)
        let resetsAt = reset.flatMap(TimeInterval.init).flatMap { seconds in
            seconds.isFinite ? Date(timeIntervalSince1970: seconds) : nil
        }

        return UsageWindow(
            used: Int((bounded * 100).rounded()),
            limit: 100,
            resetsAt: resetsAt
        )
    }
}
