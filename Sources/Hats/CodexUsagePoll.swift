import Foundation

enum CodexUsageSource: String, Equatable {
    case wham
    case gateway
}

final class CodexUsagePoll {
    static let interval: TimeInterval = 60

    let desk: CodexDesk
    var log: (String, [String: String]) -> Void = { Journal.log($0, $1) }
    private(set) var book = CodexUsageBook()
    private(set) var isReading = false
    private(set) var loggedUnknown: [String: Set<Int>] = [:]
    private var kept: Set<String> = []

    init(desk: CodexDesk) { self.desk = desk }

    func poll(_ tickets: [CodexTicket], worn: String?, then: @escaping () -> Void) {
        let world = desk.world
        let now = world.now()
        keep(Set(tickets.map(\.id)))
        let due = tickets.filter {
            book.allowsReading($0.id, at: now)
                && !book.hasAGatewaySighting(of: $0.id, youngerThan: Self.interval, at: now)
        }
        guard !isReading, !due.isEmpty else { return }
        isReading = true
        let runUsage = world.runUsage ?? { $0() }
        let send = world.sendUsage ?? world.send
        world.run { [weak self, desk] in
            let steps = due.map { ($0.id, CodexUsageStep.of($0, isWorn: $0.id == worn, desk: desk)) }
            runUsage {
                let reads = steps.map { id, step in Self.perform(step, for: id, now: world.now, send: send) }
                world.onMain {
                    guard let self else { return }
                    self.isReading = false
                    for read in reads where self.kept.contains(read.id) { self.record(read) }
                    then()
                }
            }
        }
    }

    static func perform(
        _ step: CodexUsageStep,
        for id: String,
        now: () -> Date,
        send: (URLRequest) -> (status: Int, body: Data?)
    ) -> CodexUsageRead {
        let sentAt = now()
        switch step {
        case .trouble(let trouble):
            return CodexUsageRead(id: id, sentAt: sentAt, outcome: .failed(trouble))
        case .read(let token, let accountID):
            let reply = send(CodexUsageFetch.request(token: token, accountID: accountID))
            let outcome = CodexUsageFetch.outcome(status: reply.status, body: reply.body)
            return CodexUsageRead(id: id, sentAt: sentAt, outcome: outcome)
        }
    }

    func record(_ read: CodexUsageRead) {
        if case .reading(let reading) = read.outcome { noteUnknownWindows(of: reading, for: read.id) }
        let wasBusy = book.busy.contains(read.id)
        book.record(read.outcome, for: read.id, sentAt: read.sentAt, every: Self.interval)
        guard !wasBusy, book.busy.contains(read.id) else { return }
        log("codexUsage.busy", ["hat": String(read.id.prefix(8)), "status": "429"])
    }

    @discardableResult
    func note(_ sighting: CodexUsageSighting, for id: String) -> CodexUsageNote {
        noteUnknownWindows(of: sighting.reading, for: id)
        return book.note(sighting, for: id)
    }

    func keep(_ ids: Set<String>) {
        kept = ids
        book.keep(ids)
        loggedUnknown = loggedUnknown.filter { ids.contains($0.key) }
    }

    private func noteUnknownWindows(of reading: CodexUsageReading, for id: String) {
        for window in reading.unknownWindows where loggedUnknown[id, default: []].insert(window.minutes).inserted {
            log("codexUsage.unknownWindow", [
                "hat": String(id.prefix(8)),
                "minutes": String(window.minutes),
                "percent": String(window.percent),
            ])
        }
    }
}
