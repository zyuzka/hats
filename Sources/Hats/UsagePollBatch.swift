import Foundation

struct LiveCredential: Equatable {
    let hat: String
    let fingerprint: String
}

struct UsagePollBatch {
    var readings: [String: UsageReading] = [:]
    var troubles: [String: UsageTrouble] = [:]
    var refused: Set<String> = []
    var waiting: Set<String> = []
    var renewals: [String: RenewedLogin] = [:]
    var liveCredential: LiveCredential?

    mutating func record(_ outcome: UsageFetch, for id: String, isWearing: Bool) {
        if let reading = outcome.reading { readings[id] = reading }
        if let trouble = outcome.trouble { troubles[id] = .fetchFailed(trouble) }
        if outcome.refusedAuthorization, isWearing { refused.insert(id) }
        if outcome.needsAWait { waiting.insert(id) }
    }

    mutating func setLiveCredential(
        from token: String,
        of id: String,
        isWearing: Bool
    ) {
        guard isWearing else { return }
        liveCredential = LiveCredential(hat: id, fingerprint: GatewayCredential.fingerprint(token))
    }
}
