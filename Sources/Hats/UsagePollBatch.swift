import Foundation

struct UsagePollBatch {
    var readings: [String: UsageReading] = [:]
    var troubles: [String: UsageTrouble] = [:]
    var refused: Set<String> = []
    var waiting: Set<String> = []
    var renewals: [String: RenewedLogin] = [:]

    mutating func record(_ outcome: UsageFetch, for id: String, isWearing: Bool) {
        if let reading = outcome.reading { readings[id] = reading }
        if let trouble = outcome.trouble { troubles[id] = .fetchFailed(trouble) }
        if outcome.refusedAuthorization, isWearing { refused.insert(id) }
        if outcome.needsAWait { waiting.insert(id) }
    }
}
