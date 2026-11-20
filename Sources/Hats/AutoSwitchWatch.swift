import AppKit

final class AutoSwitchWatch {
    typealias Hats = [(id: String, isWearing: Bool)]
    typealias Batch = UsagePollBatch

    private let osAccount: String
    private let queue = DispatchQueue(label: "hats.usage", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var inFlight = false
    private var pending: (hats: Hats, source: PollSource)?
    private var pollStartedAt: Date?
    private var provider: (() -> Hats)?
    private let wakes: NotificationCenter
    private var wakeObserver: NSObjectProtocol?
    private var wakePoll: DispatchWorkItem?

    private(set) var readings: [String: UsageReading] = [:]
    private(set) var parked = ParkedRises()
    private(set) var readAt: [String: Date] = [:]
    private(set) var troubles: [String: UsageTrouble] = [:]
    private(set) var backoff = RenewalBackoff()
    private(set) var missed = MissedPolls()
    private(set) var freshInTheLastPoll: Set<String> = []
    private(set) var weeklyEverRead: Set<String> = []
    private(set) var liveCredential: LiveCredential?
    private(set) var lastPoll: LastPoll?
    private(set) var aliveAt: Date?

    var interval: TimeInterval = 300
    static let afterAWake: TimeInterval = 25

    var wakeDelay: TimeInterval = AutoSwitchWatch.afterAWake
    var makeWorld: (String) -> UsageWorld = { UsageWorld.real(keychain: .real(osAccount: $0)) }
    var onReadings: ([String: UsageReading]) -> Void = { _ in Journal.log("usage.readingsIgnored") }
    var onAuthObservation: (Set<String>, Set<String>) -> Void = { _, _ in Journal.log("usage.authIgnored") }
    var onRenewals: ([String: RenewedLogin]) -> Void = { _ in Journal.log("usage.renewalsIgnored") }

    init(osAccount: String = NSUserName(), wakes: NotificationCenter) {
        self.osAccount = osAccount
        self.wakes = wakes
    }

    func start(hats: @escaping () -> Hats) {
        stop()
        provider = hats
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: interval)
        timer.setEventHandler { [weak self] in self?.poll(hats(), from: .timer) }
        timer.resume()
        self.timer = timer
        wakeObserver = wakes.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.pollAfterTheWake(hats) }
    }

    private func pollAfterTheWake(_ hats: @escaping () -> Hats) {
        wakePoll?.cancel()
        let poll = DispatchWorkItem { [weak self] in self?.poll(hats(), from: .outOfBand) }
        wakePoll = poll
        DispatchQueue.main.asyncAfter(deadline: .now() + wakeDelay, execute: poll)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let wakeObserver { wakes.removeObserver(wakeObserver) }
        wakeObserver = nil
        wakePoll?.cancel()
        wakePoll = nil
    }

    func poll(_ hats: Hats, from source: PollSource = .outOfBand) {
        guard !inFlight else {
            pending = (hats, source)
            return
        }
        inFlight = true
        let osAccount = osAccount
        let makeWorld = makeWorld
        let started = Date()
        pollStartedAt = started
        let allowed = backoff.allowing(hats.map(\.id), at: started)
        queue.async { [weak self] in
            var world = makeWorld(osAccount)
            world.mayRenew = { allowed.contains($0) }
            let batch = Self.fetched(hats, world: world)
            DispatchQueue.main.async { self?.landed(batch, polled: hats, from: source) }
        }
    }

    func forgetTheMissedPolls() { missed.forget() }

    static func readingsAfterAPoll(
        _ existing: [String: UsageReading],
        keeping ids: Set<String>,
        batch: Batch
    ) -> [String: UsageReading] {
        existing.kept(for: ids)
            .filter { batch.troubles[$0.key]?.keepsAnEarlierReading ?? true }
            .merging(batch.readings) { _, new in new }
    }

    static func getWeeklyEverRead(
        _ existing: Set<String>,
        keeping ids: Set<String>,
        batch: Batch
    ) -> Set<String> {
        existing.intersection(ids).union(batch.readings.filter { $0.value.weekly != nil }.keys)
    }

    func landed(_ batch: Batch, polled: Hats, from source: PollSource) {
        inFlight = false
        if !batch.renewals.isEmpty { onRenewals(batch.renewals) }
        Self.noteOutcomes(into: &backoff, batch: batch, every: interval, at: pollStartedAt ?? Date())
        guard timer != nil else {
            pending = nil
            return
        }
        if let now = provider?(), Self.shape(now) != Self.shape(polled) {
            Journal.log("usage.pollDiscarded", ["reason": "the hats moved while it ran"])
            pending = nil
            poll(now, from: source)
            return
        }
        let ids = Set(polled.map(\.id))
        readings = Self.readingsAfterAPoll(readings, keeping: ids, batch: batch)
        weeklyEverRead = Self.getWeeklyEverRead(weeklyEverRead, keeping: ids, batch: batch)
        liveCredential = batch.liveCredential
        let fresh = Set(batch.readings.keys)
        let stamp = Date()
        lastPoll = LastPoll(at: stamp, liveSlot: batch.liveSlot)
        if polled.contains(where: { $0.isWearing && fresh.contains($0.id) }) { aliveAt = stamp }
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
        noteTheWornHat(polled, fresh: fresh, from: source, at: stamp)
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
            poll(pending.hats, from: pending.source)
        }
    }

    private func noteTheWornHat(_ polled: Hats, fresh: Set<String>, from source: PollSource, at stamp: Date) {
        freshInTheLastPoll = fresh
        missed = missed.settled(
            wearing: polled.first(where: \.isWearing)?.id,
            fresh: fresh,
            from: source,
            every: interval,
            at: stamp
        )
    }

    static func noteOutcomes(into backoff: inout RenewalBackoff,
                             batch: Batch,
                             every interval: TimeInterval,
                             at now: Date) {
        for id in batch.renewals.keys { backoff.succeeded(id) }
        for id in batch.readings.keys where !batch.waiting.contains(id) { backoff.succeeded(id) }
        for (id, trouble) in batch.troubles {
            guard case .renewalFailed = trouble else { continue }
            backoff.failed(id, at: now, pollingEvery: interval)
        }
        for id in batch.waiting { backoff.failed(id, at: now, pollingEvery: interval) }
    }

    var roseWhileParked: [String: Int] { parked.rises }

    static func shape(_ hats: Hats) -> [String] { hats.map { "\($0.id):\($0.isWearing)" } }

    static func stamps<Keys: Sequence>(for ids: Keys, at date: Date) -> [String: Date] where Keys.Element == String {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, date) })
    }
}
