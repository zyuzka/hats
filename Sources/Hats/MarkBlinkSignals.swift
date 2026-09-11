import AppKit

extension MarkBlink {
    enum Pause: String, CaseIterable {
        case machineAsleep
        case screensOff
        case screenLocked
        case sessionInactive
    }

    struct Signal {
        let name: Notification.Name
        let reason: Pause
        let pauses: Bool
    }

    static let motionChanged = NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
    static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    static let workspaceSignals = [
        Signal(name: NSWorkspace.willSleepNotification, reason: .machineAsleep, pauses: true),
        Signal(name: NSWorkspace.didWakeNotification, reason: .machineAsleep, pauses: false),
        Signal(name: NSWorkspace.screensDidSleepNotification, reason: .screensOff, pauses: true),
        Signal(name: NSWorkspace.screensDidWakeNotification, reason: .screensOff, pauses: false),
        Signal(name: NSWorkspace.sessionDidResignActiveNotification, reason: .sessionInactive, pauses: true),
        Signal(name: NSWorkspace.sessionDidBecomeActiveNotification, reason: .sessionInactive, pauses: false),
    ]

    static let distributedSignals = [
        Signal(name: MarkBlink.screenLocked, reason: .screenLocked, pauses: true),
        Signal(name: MarkBlink.screenUnlocked, reason: .screenLocked, pauses: false),
    ]
}
