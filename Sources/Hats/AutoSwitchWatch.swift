import Foundation

final class AutoSwitchWatch {
    typealias Hats = [(id: String, isWearing: Bool)]
    typealias Batch = UsagePollBatch

    private let osAccount: String
    private let queue = DispatchQueue(label: "hats.usage", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var inFlight = false
    private var pending: Hats?
    private var provider: (() -> Hats)?

    private(set) var readings: [String: UsageReading] = [:]
    private(set) var parked = ParkedRises()
    private(set) var readAt: [String: Date] = [:]
    private(set) var troubles: [String: UsageTrouble] = [:]
    private(set) var backoff = RenewalBackoff()

    var interval: TimeInterval = 300
    var onReadings: ([String: UsageReading]) -> Void = { _ in Journal.log("usage.readingsIgnored") }
    var onAuthObservation: (Set<String>, Set<String>) -> Void = { _, _ in Journal.log("usage.authIgnored") }
    var onRenewals: ([String: RenewedLogin]) -> Void = { _ in Journal.log("usage.renewalsIgnored") }

    init(osAccount: String = NSUserName()) { self.osAccount = osAccount }

    func start(hats: @escaping () -> Hats) {
        stop()
        provider = hats
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: interval)
        timer.setEventHandler { [weak self] in self?.poll(hats()) }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func poll(_ hats: Hats) {
        guard !inFlight else {
            pending = hats
            return
        }
        inFlight = true
        let osAccount = osAccount
        let allowed = backoff.allowing(hats.map(\.id), at: Date())
        queue.async { [weak self] in
            var world = UsageWorld.real(osAccount: osAccount)
            world.mayRenew = { allowed.contains($0) }
            let batch = Self.fetched(hats, world: world)
            DispatchQueue.main.async { self?.landed(batch, polled: hats) }
        }
    }

    static func readingsAfterAPoll(
        _ existing: [String: UsageReading],
        keeping ids: Set<String>,
        batch: Batch
    ) -> [String: UsageReading] {
        existing.kept(for: ids)
            .filter { batch.troubles[$0.key]?.keepsAnEarlierReading ?? true }
            .merging(batch.readings) { _, new in new }
    }

    private func landed(_ batch: Batch, polled: Hats) {
        inFlight = false
        if !batch.renewals.isEmpty { onRenewals(batch.renewals) }
        Self.noteRenewalOutcomes(into: &backoff, batch: batch, every: interval, at: Date())
        guard timer != nil else {
            pending = nil
            return
        }
        if let now = provider?(), Self.shape(now) != Self.shape(polled) {
            Journal.log("usage.pollDiscarded", ["reason": "the hats moved while it ran"])
            pending = nil
            poll(now)
            return
        }
        let ids = Set(polled.map(\.id))
        readings = Self.readingsAfterAPoll(readings, keeping: ids, batch: batch)
        let fresh = Set(batch.readings.keys)
        let stamp = Date()
        parked = parked.settled(
            after: PollObservation(
                readings: readings,
                fresh: fresh,
                worn: Set(polled.filter(\.isWearing).map(\.id)),
                ids: ids
            ),
            at: stamp
        )
        readAt = readAt.kept(for: ids).merging(Self.stamps(for: fresh, at: stamp)) { _, new in new }
        backoff.keep(ids)
        let troublesBefore = troubles
        troubles = troubles.kept(for: ids.subtracting(fresh)).merging(batch.troubles) { _, new in new }
        for change in UsageObservation.changes(from: troublesBefore, to: troubles, polled: ids) {
            Journal.log(change.journalEvent, change.details)
        }
        onAuthObservation(batch.refused, fresh)
        onReadings(readings)
        if let pending {
            self.pending = nil
            poll(pending)
        }
    }

    static func noteRenewalOutcomes(into backoff: inout RenewalBackoff,
                                    batch: Batch,
                                    every interval: TimeInterval,
                                    at now: Date) {
        for id in batch.renewals.keys { backoff.succeeded(id) }
        for (id, trouble) in batch.troubles {
            guard case .renewalFailed = trouble else { continue }
            backoff.failed(id, at: now, pollingEvery: interval)
        }
    }

    var roseWhileParked: [String: Int] { parked.rises }

    static func shape(_ hats: Hats) -> [String] { hats.map { "\($0.id):\($0.isWearing)" } }

    static func stamps<Keys: Sequence>(for ids: Keys, at date: Date) -> [String: Date] where Keys.Element == String {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, date) })
    }
}
