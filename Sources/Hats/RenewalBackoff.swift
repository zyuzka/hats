import Foundation

struct RenewalBackoff: Equatable {
    static let longestWaitInPolls = 12
    static let earlyByAPartOfAPoll = 0.1

    private var consecutiveFailures: [String: Int] = [:]
    private var notBefore: [String: Date] = [:]

    static func pollsToWait(after failures: Int) -> Int {
        guard failures > 0 else { return 0 }
        let doubled = 1 << min(failures - 1, 16)

        return min(doubled, longestWaitInPolls)
    }

    func allows(_ id: String, at now: Date) -> Bool {
        guard let until = notBefore[id] else { return true }

        return until <= now
    }

    func allowing<Ids: Sequence>(_ ids: Ids, at now: Date) -> Set<String> where Ids.Element == String {
        Set(ids.filter { allows($0, at: now) })
    }

    mutating func failed(_ id: String, at now: Date, pollingEvery interval: TimeInterval) {
        let failures = (consecutiveFailures[id] ?? 0) + 1
        consecutiveFailures[id] = failures
        let polls = TimeInterval(Self.pollsToWait(after: failures)) - Self.earlyByAPartOfAPoll
        notBefore[id] = now.addingTimeInterval(interval * polls)
    }

    mutating func succeeded(_ id: String) {
        consecutiveFailures.removeValue(forKey: id)
        notBefore.removeValue(forKey: id)
    }

    mutating func keep(_ ids: Set<String>) {
        consecutiveFailures = consecutiveFailures.filter { ids.contains($0.key) }
        notBefore = notBefore.filter { ids.contains($0.key) }
    }
}
