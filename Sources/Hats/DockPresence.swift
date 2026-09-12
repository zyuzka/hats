import AppKit

struct WindowFace: Equatable {
    let isVisible: Bool
    let canBecomeMain: Bool
}

enum DockPresence {
    static func isNeeded(for windows: [WindowFace]) -> Bool {
        windows.contains { $0.isVisible && $0.canBecomeMain }
    }

    static func watch() {
        let centre = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            centre.addObserver(forName: name, object: nil, queue: .main) { _ in
                DispatchQueue.main.async { refresh() }
            }
        }
    }

    static func refresh() {
        let faces = NSApp.windows.map {
            WindowFace(isVisible: $0.isVisible, canBecomeMain: $0.canBecomeMain)
        }
        let wanted: NSApplication.ActivationPolicy = isNeeded(for: faces) ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        Journal.log("dock.presence", ["shown": String(wanted == .regular)])
    }
}
