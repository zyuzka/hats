import Foundation

enum StageLimit: String, CaseIterable, Codable, Equatable {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
}

enum LimitStage: String, CaseIterable, Codable, Equatable {
    case warned
    case asked
}

enum LimitReason: String, CaseIterable, Equatable {
    case noHat = "no_hat"
    case autoSwitchOff = "auto_switch_off"
    case switchThresholdOff = "switch_threshold_off"
    case hatsNotRunning = "hats_not_running"
}

enum LimitWaitOrigin: String, CaseIterable, Equatable {
    case hat
    case warned
    case deferred
}

struct LimitWait: Equatable {
    let until: Date
    let origin: LimitWaitOrigin
    let drainMinutes: Int
    let cancelledAt: Date?
}

struct LimitEvent: Equatable {
    let stage: LimitStage
    let at: Date
    let percent: Double
    let worn: String
    let reason: LimitReason
    var early = false
    var minutesToSave: Int?
    var target: Int?
    var leadSeconds: Int?
    var wait: LimitWait?
}

struct LimitEpisode: Equatable {
    let limit: StageLimit
    let resetsAt: Date
    let percent: Double
    let warnPercent: Int?
    let savePercent: Int?
    let events: [LimitEvent]
}
