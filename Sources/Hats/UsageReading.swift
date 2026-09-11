import Foundation

struct UsageWindow: Equatable {
    let used: Int
    let limit: Int
    let resetsAt: Date?

    var percent: Int {
        guard limit > 0 else { return 0 }
        return min(100, max(0, used * 100 / limit))
    }

    static func parsed(_ bucket: Any?) -> UsageWindow? {
        guard let bucket = bucket as? [String: Any],
              let utilization = Self.wholeNumber(bucket["utilization"])
        else { return nil }
        return UsageWindow(
            used: utilization,
            limit: 100,
            resetsAt: (bucket["resets_at"] as? String).flatMap(UsageReading.date(from:))
        )
    }

    private static func wholeNumber(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double, double.isFinite { return Int(double.rounded()) }
        return nil
    }
}

struct UsageReading: Equatable {
    let session: UsageWindow?
    let weekly: UsageWindow?

    var hasAnyWindow: Bool { session != nil || weekly != nil }

    static func parsed(_ payload: [String: Any]) -> UsageReading? {
        let reading = UsageReading(
            session: UsageWindow.parsed(payload["five_hour"]),
            weekly: UsageWindow.parsed(payload["seven_day"])
        )
        return reading.hasAnyWindow ? reading : nil
    }

    var journalLine: String {
        var parts: [String] = []
        if let session { parts.append("session=\(session.used)/\(session.limit)") }
        if let weekly { parts.append("weekly=\(weekly.used)/\(weekly.limit)") }
        return parts.joined(separator: " ")
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoWhole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from text: String) -> Date? {
        iso.date(from: text) ?? isoWhole.date(from: text)
    }

    static func when(_ date: Date, sameDayAs reference: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = clock(date, timeZone: timeZone)
        guard !calendar.isDate(date, inSameDayAs: reference) else { return "at \(time)" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE d MMM"
        return "on \(formatter.string(from: date)) at \(time)"
    }

    static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
