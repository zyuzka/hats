import AppKit

final class CodexHats {
    let desk: CodexDesk
    let gateway: CodexGatewayRun
    let signIn = CodexSignInFlow()
    private var timer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?

    init(world: CodexWorld) {
        desk = CodexDesk(world: world)
        gateway = CodexGatewayRun(broker: CodexGatewayDesk(desk: desk, state: CodexGatewayState()))
    }

    func start(every interval: TimeInterval, tick: @escaping () -> Void) {
        desk.interval = interval
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5, repeating: interval)
        timer.setEventHandler(handler: tick)
        timer.resume()
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in tick() }
    }
}
