import Foundation

struct ParkedBaseline: Equatable {
    let percent: Int
    let at: Date
}

struct PollObservation {
    let readings: [String: UsageReading]
    let fresh: Set<String>
    let worn: Set<String>
    let ids: Set<String>
}

struct ParkedRises: Equatable {
    private(set) var from: [String: ParkedBaseline] = [:]
    private(set) var rises: [String: Int] = [:]

    func settled(after poll: PollObservation, at now: Date) -> ParkedRises {
        var next = ParkedRises(
            from: from.kept(for: poll.ids),
            rises: rises.kept(for: poll.ids)
        )
        for id in poll.ids {
            if poll.worn.contains(id) {
                next.from[id] = nil
                next.rises[id] = nil
                continue
            }
            guard poll.fresh.contains(id),
                  let percent = poll.readings[id]?.session?.percent
            else { continue }
            guard let baseline = next.from[id] else {
                next.from[id] = ParkedBaseline(percent: percent, at: now)
                next.rises[id] = nil
                continue
            }
            if percent > baseline.percent {
                next.rises[id] = percent - baseline.percent
            } else if percent < baseline.percent {
                next.from[id] = ParkedBaseline(percent: percent, at: now)
                next.rises[id] = nil
            } else {
                next.rises[id] = nil
            }
        }
        return next
    }
}
