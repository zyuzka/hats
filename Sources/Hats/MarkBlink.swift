import AppKit

final class MarkBlink {
    static let interval: TimeInterval = 0.5
    static let leeway: DispatchTimeInterval = .milliseconds(100)

    private weak var button: NSStatusBarButton?
    private var timer: DispatchSourceTimer?
    private var state: MarkState?
    private var withCursor: NSImage?
    private var withoutCursor: NSImage?
    private var paused: Set<Pause> = []
    private var isWantedBySetting = true
    private var fromWorkspace: [NSObjectProtocol] = []
    private var fromDistributed: [NSObjectProtocol] = []

    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private(set) var isShowingCursor = true
    private(set) var timersStarted = 0
    private(set) var lastPainted: NSImage?

    var observerCount: Int { fromWorkspace.count + fromDistributed.count }

    private(set) var signalsHandled = 0

    static func isBlinkingWanted(setting: Bool, reduceMotion: Bool, awake: Bool) -> Bool {
        setting && !reduceMotion && awake
    }

    init(button: NSStatusBarButton?) {
        self.button = button
    }

    deinit { stop() }

    func show(_ state: MarkState, blinking setting: Bool) {
        if state != self.state {
            self.state = state
            withCursor = Mark.image(state: state, cursorVisible: true)
            withoutCursor = Mark.image(state: state, cursorVisible: false)
        }
        isWantedBySetting = setting
        settle()
    }

    func advanceTheBlink() {
        isShowingCursor.toggle()
        paint()
    }

    func pause(_ reason: Pause) {
        guard paused.insert(reason).inserted else { return }
        settle()
    }

    func resume(_ reason: Pause) {
        guard paused.remove(reason) != nil else { return }
        settle()
    }

    var isPaused: Bool { !paused.isEmpty }

    func watchTheSystem() {
        stopWatching()
        let workspace = NSWorkspace.shared.notificationCenter
        fromWorkspace = Self.workspaceSignals.map { observing(workspace, $0.name, $0) }
        fromWorkspace.append(observing(workspace, Self.motionChanged) { [weak self] in self?.settle() })
        let distributed = DistributedNotificationCenter.default()
        fromDistributed = Self.distributedSignals.map { observing(distributed, $0.name, $0) }
    }

    func stop() {
        cancelTheTimer()
        stopWatching()
    }

    private func stopWatching() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in fromWorkspace { workspace.removeObserver(observer) }
        let distributed = DistributedNotificationCenter.default()
        for observer in fromDistributed { distributed.removeObserver(observer) }
        fromWorkspace = []
        fromDistributed = []
    }

    private func observing(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ signal: Signal
    ) -> NSObjectProtocol {
        observing(center, name) { [weak self] in
            guard let self else { return }
            if signal.pauses { pause(signal.reason) } else { resume(signal.reason) }
        }
    }

    private func observing(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ act: @escaping () -> Void
    ) -> NSObjectProtocol {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.signalsHandled += 1
            act()
        }
    }

    private var isBlinking: Bool {
        Self.isBlinkingWanted(setting: isWantedBySetting, reduceMotion: reducesMotion(), awake: !isPaused)
    }

    private func settle() {
        guard isBlinking else {
            cancelTheTimer()
            isShowingCursor = true
            paint()
            return
        }
        startTheTimerUnlessItAlreadyRuns()
        paint()
    }

    private func startTheTimerUnlessItAlreadyRuns() {
        guard timer == nil else { return }
        let ticking = DispatchSource.makeTimerSource(queue: .main)
        ticking.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: Self.leeway)
        ticking.setEventHandler { [weak self] in self?.advanceTheBlink() }
        ticking.resume()
        timer = ticking
        timersStarted += 1
    }

    private func cancelTheTimer() {
        timer?.cancel()
        timer = nil
    }

    private func paint() {
        let shown = isShowingCursor ? withCursor : withoutCursor
        lastPainted = shown
        button?.image = shown
    }
}
