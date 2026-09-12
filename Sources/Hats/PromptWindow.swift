import AppKit
import SwiftUI

final class PromptWindow: NSObject, NSWindowDelegate {
    private static let keeper = PromptWindow()

    static func ask(_ prompt: HatPrompt) -> Int {
        show(buttons: prompt.buttons.count) { choose in
            PromptView(prompt: prompt, choose: choose)
        }
    }

    static func show<Content: View>(
        buttons: Int,
        @ViewBuilder content: (@escaping (Int) -> Void) -> Content
    ) -> Int {
        var chosen = PromptButtons.dismissed(of: buttons)
        let asked = NSApp.keyWindow
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(rootView: content { index in
            chosen = index
            NSApp.stopModal()
        })
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = keeper
        window.center()
        window.level = .modalPanel
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        asked?.makeKeyAndOrderFront(nil)

        return chosen
    }

    func windowWillClose(_ notification: Notification) {
        guard NSApp.modalWindow === notification.object as? NSWindow else { return }
        NSApp.stopModal()
    }
}
