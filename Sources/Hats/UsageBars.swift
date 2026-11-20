import Foundation

enum UsageBarTone: Equatable {
    case neutral
    case warning
    case critical

    static let warningFrom = Mark.meterFrom
    static let criticalFrom = 90

    static func of(percent: Int) -> UsageBarTone {
        if percent >= criticalFrom { return .critical }
        if percent >= warningFrom { return .warning }

        return .neutral
    }
}

enum UsageBarFill: Equatable {
    case solid
    case faint
    case emptyDashed
}

struct UsageBar: Equatable {
    let label: String
    let percent: Int
    let tone: UsageBarTone
    let fill: UsageBarFill
    let resets: String?

    static func session(_ window: UsageWindow, timeZone: TimeZone, now: Date) -> UsageBar {
        let percent = clamped(window.percent)
        let resets = window.resetsAt.flatMap { $0 > now ? UsageReading.clock($0, timeZone: timeZone) : nil }

        return UsageBar(label: "5h", percent: percent, tone: .of(percent: percent), fill: .solid, resets: resets)
    }

    static func week(_ sighting: WeekSighting, timeZone: TimeZone, now: Date) -> UsageBar {
        let resets = sighting.window.resetsAt.map { UsageReading.dayAndClock($0, timeZone: timeZone) }
        if let resetsAt = sighting.window.resetsAt, resetsAt <= now {
            return UsageBar(label: "week", percent: 0, tone: .neutral, fill: .emptyDashed, resets: resets)
        }
        let percent = clamped(sighting.window.percent)

        return UsageBar(
            label: "week",
            percent: percent,
            tone: .of(percent: percent),
            fill: sighting.isConfirmed ? .solid : .faint,
            resets: resets
        )
    }

    private static func clamped(_ percent: Int) -> Int { min(max(percent, 0), 100) }
}

enum RowDetailLine: Equatable {
    case text(String, spoken: String? = nil)
    case bar(UsageBar)
}

enum RowDetail {
    static func lines(
        of row: HatRowState,
        display: UsageDisplay,
        handover: String?,
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) -> [RowDetailLine] {
        let week = weekLines(of: row, display: display, timeZone: timeZone, now: now)
        let stale = HatsCopy.staleReading(row.usageTrouble, timeZone: timeZone, now: now)
            .map { [RowDetailLine.text($0)] } ?? []
        if row.isWearing, let usage = row.usage {
            let session = sessionLines(usage, rose: nil, display: display, timeZone: timeZone, now: now)
            return session + week + stale + (handover.map { [.text($0)] } ?? [])
        }
        if row.isWearing, let trouble = row.usageTrouble {
            return [.text(trouble.line(timeZone: timeZone, now: now))] + week
        }
        if !row.isWearing, let usage = row.usage, usage.session != nil {
            let rose = row.roseWhileParked
            return sessionLines(usage, rose: rose, display: display, timeZone: timeZone, now: now) + week + stale
        }
        if let trouble = row.usageTrouble {
            return [.text(trouble.line(timeZone: timeZone, now: now))] + week
        }

        return week
    }

    private static func sessionLines(
        _ usage: UsageReading,
        rose: Int?,
        display: UsageDisplay,
        timeZone: TimeZone,
        now: Date
    ) -> [RowDetailLine] {
        switch display {
        case .percent:
            let line = rose == nil
                ? HatsCopy.usageLine(usage, timeZone: timeZone, now: now)
                : HatsCopy.parkedUsage(usage, rose: rose, timeZone: timeZone, now: now)
            let spoken = rose == nil
                ? HatsCopy.getUsageSpoken(usage, timeZone: timeZone, now: now)
                : HatsCopy.getParkedSpoken(usage, rose: rose, timeZone: timeZone, now: now)
            return line.map { [.text($0, spoken: spoken)] } ?? []
        case .bars:
            return usage.session.map { [.bar(.session($0, timeZone: timeZone, now: now))] } ?? []
        }
    }

    private static func weekLines(
        of row: HatRowState,
        display: UsageDisplay,
        timeZone: TimeZone,
        now: Date
    ) -> [RowDetailLine] {
        switch display {
        case .percent:
            return row.week.map { [.text($0, spoken: row.weekSpoken)] } ?? []
        case .bars:
            return row.weekSighting.map { [.bar(.week($0, timeZone: timeZone, now: now))] } ?? []
        }
    }
}
