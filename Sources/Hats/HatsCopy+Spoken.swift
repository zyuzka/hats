import Foundation

extension HatsCopy {
    static func getUsageSpoken(
        _ reading: UsageReading,
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) -> String? {
        guard let session = reading.session else { return nil }
        var spoken = "5-hour limit \(session.percent) percent"
        if let resets = session.resetsAt, resets > now {
            spoken += ", resets at \(UsageReading.clock(resets, timeZone: timeZone))"
        }

        return spoken
    }

    static func getParkedSpoken(
        _ reading: UsageReading,
        rose: Int?,
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) -> String? {
        guard let spoken = getUsageSpoken(reading, timeZone: timeZone, now: now) else { return nil }
        guard let rose, rose > 0 else { return spoken }

        return spoken + ", up \(rose) percent while not being worn"
    }

    static func getWeekSpoken(
        percent: Int,
        resetsAt: Date?,
        isConfirmed: Bool,
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) -> String {
        let unconfirmed = isConfirmed ? "" : ", not confirmed"
        guard let resetsAt else { return "weekly limit \(percent) percent" + unconfirmed }
        let when = UsageReading.dayAndClock(resetsAt, timeZone: timeZone)
        guard resetsAt > now else { return "weekly limit unknown, last reset \(when)" }

        return "weekly limit \(percent) percent" + unconfirmed + ", resets \(when)"
    }
}
