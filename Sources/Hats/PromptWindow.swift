import AppKit
import SwiftUI

enum PromptWindow {
    static func ask(_ prompt: HatPrompt) -> Int {
        var chosen = PromptButtons.dismissed(of: prompt.buttons.count)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(
            rootView: PromptView(prompt: prompt) { index in
                chosen = index
                NSApp.stopModal()
            }
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
        window.orderOut(nil)

        return chosen
    }
}
