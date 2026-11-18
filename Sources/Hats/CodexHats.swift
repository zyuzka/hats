import AppKit

final class CodexHats {
    let desk: CodexDesk
    let gateway: CodexGatewayRun
    let signIn = CodexSignInFlow()
    let usage: CodexUsagePoll
    private var repeating: [String: (timer: DispatchSourceTimer, wake: NSObjectProtocol)] = [:]

    var repeatingCount: Int { repeating.count }

    init(world: CodexWorld) {
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
        guard let held = repeating.removeValue(forKey: name) else { return }
        held.timer.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(held.wake)
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
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in tick() }
        repeating[name] = (timer, wake)
    }
}
