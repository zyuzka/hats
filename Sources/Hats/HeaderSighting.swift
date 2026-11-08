import Foundation

struct HeaderSightingWorld {
    let policy: AutoSwitchPolicy
    let wearing: String?
    let liveCredential: LiveCredential?
    let readings: [String: UsageReading]
    let interval: TimeInterval
}

enum HeaderSighting: Equatable {
    case autoSwitchIsOff
    case credentialUnknown
    case anotherCredential
    case underTheThresholds
    case alreadyKnown
    case tooSoon
    case pollNow
}

struct PollsOnHeaders {
    static let quietPeriod: TimeInterval = 30

    private var last: (hat: String, at: Date)?

    mutating func getDecision(
        credential: String,
        reading: UsageReading,
        world: HeaderSightingWorld,
        at now: Date
    ) -> HeaderSighting {
        guard world.policy.isOn else { return .autoSwitchIsOff }
        guard let live = world.liveCredential, live.hat == world.wearing else { return .credentialUnknown }
        guard live.fingerprint == credential else { return .anotherCredential }
        guard !world.policy.crossedLimits(in: reading).isEmpty else { return .underTheThresholds }
        if let known = world.readings[live.hat], !world.policy.crossedLimits(in: known).isEmpty {
            return .alreadyKnown
        }
        let tooSoon = isTooSoon(
            for: live.hat,
            at: now,
            interval: world.interval
        )
        guard !tooSoon else { return .tooSoon }
        last = (live.hat, now)

        return .pollNow
    }

    private func isTooSoon(
        for hat: String,
        at now: Date,
        interval: TimeInterval
    ) -> Bool {
        guard let last else { return false }
        let since = now.timeIntervalSince(last.at)
        if (0..<Self.quietPeriod).contains(since) { return true }

        return last.hat == hat && (0..<interval).contains(since)
    }
}
