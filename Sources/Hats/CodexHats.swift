import AppKit

final class CodexHats {
    let desk: CodexDesk
    let gateway: CodexGatewayRun
    let signIn = CodexSignInFlow()
    let usage: CodexUsagePoll
    private var repeating: [String: CodexRepeating] = [:]
    private let wakes: NotificationCenter

    var repeatingCount: Int { repeating.count }
    var wakeDelay: TimeInterval = AutoSwitchWatch.afterAWake

    init(world: CodexWorld, wakes: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.wakes = wakes
        desk = CodexDesk(world: world)
        gateway = CodexGatewayRun(broker: CodexGatewayDesk(desk: desk, state: CodexGatewayState()))
        usage = CodexUsagePoll(desk: desk)
    }

    func start(every interval: TimeInterval, tick: @escaping () -> Void) {
        desk.interval = interval
        repeatEvery(interval, firstAfter: 5, as: "renew", tick: tick)
    }

    func startReadingUsage(every interval: TimeInterval, tick: @escaping () -> Void) {
        repeatEvery(interval, firstAfter: 3, as: "usage", tick: tick)
    }

    func stop() {
        for name in Array(repeating.keys) { stopRepeating(name) }
    }

    private func stopRepeating(_ name: String) {
        repeating.removeValue(forKey: name)?.cancel(wakes: wakes)
    }

    private func repeatEvery(
        _ interval: TimeInterval,
        firstAfter delay: TimeInterval,
        as name: String,
        tick: @escaping () -> Void
    ) {
        stopRepeating(name)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay, repeating: interval)
        timer.setEventHandler(handler: tick)
        timer.resume()
        let held = CodexRepeating(timer: timer)
        held.wake = wakes.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak held] _ in
            guard let self, let held else { return }
            held.tickAfterAWake(in: self.wakeDelay, tick: tick)
        }
        repeating[name] = held
    }
}

private final class CodexRepeating {
    let timer: DispatchSourceTimer
    var wake: NSObjectProtocol?
    private var afterAWake: DispatchWorkItem?

    init(timer: DispatchSourceTimer) {
        self.timer = timer
    }

    func tickAfterAWake(in delay: TimeInterval, tick: @escaping () -> Void) {
        afterAWake?.cancel()
        let item = DispatchWorkItem(block: tick)
        afterAWake = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel(wakes: NotificationCenter) {
        timer.cancel()
        afterAWake?.cancel()
        afterAWake = nil
        if let wake { wakes.removeObserver(wake) }
        wake = nil
    }
}
