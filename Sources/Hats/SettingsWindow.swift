import AppKit
import SwiftUI

struct SettingsTabs: View {
    @ObservedObject var model: HatsModel

    var body: some View {
        TabView {
            GeneralPanel(model: model)
                .tabItem { Text("General") }
            ManageHatsPanel(model: model, open: nil)
                .tabItem { Text("Hats") }
            AutoSwitchPanel(model: model)
                .tabItem { Text("Auto-switch") }
            GatewayPanel(model: model)
                .tabItem { Text("Gateway") }
        }
        .padding(14)
        .frame(width: 460, height: 420)
    }
}

final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: HatsModel) {
        DockPresence.aWindowIsAboutToOpen()
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
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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
