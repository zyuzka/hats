import AppKit

final class SessionHandoffWork {
    private let queue = DispatchQueue(label: "dev.tmk.hats.session-handoff")
    private let lock = NSLock()
    private let inner: PluginWorld
    private let center: NotificationCenter
    private var stopped = false
    private var observer: NSObjectProtocol?

    init(world: PluginWorld, center: NotificationCenter = .default) {
        inner = world
        self.center = center
        observer = center.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in self?.stop() }
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
    }

    var world: PluginWorld {
        var guarded = inner
        let run = inner.run
        guarded.run = { [weak self] line in
            guard let self, !self.isStopped else { return PluginCommandOutcome(end: .notStarted("Hats is quitting")) }
            return run(line)
        }

        return guarded
    }

    func perform(_ work: @escaping (PluginWorld) -> Void) {
        let world = self.world
        queue.async { work(world) }
    }
}
