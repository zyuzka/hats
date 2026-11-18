import Foundation

extension HatsCopy {
    static let hatLimit = "Hat limit"
    static let limitThresholdsNote =
        "Acts when Hats will not switch the worn hat away from that limit: no other hat is free, auto-switch is off, "
            + "or its switch threshold is off. Sessions on the worn hat are told, and anchor at the end of a turn."

    static func getLimitWord(_ limit: StageLimit) -> String {
        switch limit {
        case .fiveHour:
            return "5-hour"
        case .sevenDay:
            return "weekly"
        }
    }

    static func getLimitReason(_ reason: LimitReason) -> String {
        switch reason {
        case .noHat:
            return "No other hat to switch to"
        case .autoSwitchOff:
            return "Auto-switch is off"
        case .switchThresholdOff:
            return "Hats does not switch on this limit"
        case .hatsNotRunning:
            return "Hats was not running"
        }
    }

    static func getLimitNoticeTitle(hat: String, limit: StageLimit, percent: Int) -> String {
        "\(hat) — \(getLimitWord(limit)) \(percent)%"
    }

    static func getEarlyLimitNoticeBody(reason: LimitReason, target: Int, minutes: Int) -> String {
        "Spending fast: \(target)% in about \(minutes) min. \(getLimitReason(reason))."
    }

    static func getLimitWaitNoticeBody(reason: LimitReason, origin: LimitWaitOrigin, minutes: Int) -> String {
        let asked = getLimitNoticeBody(stage: .asked, reason: reason, save: nil)

        return "\(asked.dropLast()), after their background work (up to \(minutes) min\(getWaitOriginWords(origin)))."
    }

    private static func getWaitOriginWords(_ origin: LimitWaitOrigin) -> String {
        switch origin {
        case .hat:
            return " from the first warning on this hat"
        case .warned:
            return " from their warning"
        case .deferred:
            return ""
        }
    }

    static func getLimitNoticeBody(stage: LimitStage, reason: LimitReason, save: Int?) -> String {
        let why = getLimitReason(reason)
        switch stage {
        case .asked:
            return "\(why). Sessions anchor at the end of their turn."
        case .warned:
            guard let save else { return "\(why). Sessions are told." }

            return "\(why). Sessions anchor at \(save)%."
        }
    }
}
