import AppKit
import SwiftUI

final class SignInWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var closing = false

    var wasClosedByAPerson: () -> Void = { Journal.log("signIn.closeIgnored") }

    func show(_ model: SignInModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: SignInView(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "Sign in"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        guard let window else { return }
        closing = true
        window.close()
        self.window = nil
        closing = false
    }

    func windowWillClose(_ notification: Notification) {
        guard !closing else { return }
        window = nil
        wasClosedByAPerson()
    }
}
