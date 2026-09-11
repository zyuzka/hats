import AppKit
import SwiftUI

struct SettingsTabs: View {
    @ObservedObject var model: HatsModel

    var body: some View {
        TabView {
            GeneralPanel(model: model)
                .tabItem { Text("General") }
            GatewayPanel(model: model)
                .tabItem { Text("Gateway") }
            AutoSwitchPanel(model: model)
                .tabItem { Text("Auto-switch") }
            ManageHatsPanel(model: model, open: nil)
                .tabItem { Text("Hats") }
        }
        .padding(14)
        .frame(width: 460, height: 420)
    }
}

final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: HatsModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsTabs(model: model)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Hats Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
