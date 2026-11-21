import AppKit
import SwiftUI

struct SettingsTabs: View {
    @ObservedObject var model: HatsModel
    @ObservedObject var drafts: SettingsDrafts

    var body: some View {
        TabView {
            GeneralPanel(model: model)
                .tabItem { Text("General") }
            ManageHatsPanel(model: model, open: nil)
                .tabItem { Text("Hats") }
            AutoSwitchPanel(model: model, drafts: drafts)
                .tabItem { Text("Auto-switch") }
            ContextThresholdsPanel(model: model, drafts: drafts)
                .tabItem { Text("Context") }
            GatewaysPanel(model: model, drafts: drafts)
                .tabItem { Text("Gateway") }
        }
        .padding(14)
        .frame(width: 460, height: 420)
        .onChange(of: model.snapshot.settings) { now in drafts.prune(in: now) }
    }
}

final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: HatsModel?
    private var drafts = SettingsDrafts()

    func show(model: HatsModel) {
        DockPresence.aWindowIsAboutToOpen()
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        self.model = model
        drafts = SettingsDrafts()
        let view = SettingsTabs(model: model, drafts: drafts)
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.makeFirstResponder(nil)
        guard let model else { return true }
        let leftovers = drafts.getLeftovers(in: model.snapshot.settings)
        guard !leftovers.isEmpty else { return true }
        switch SettingsCloseQuestion.findAnswer(leftovers) {
        case .discard:
            drafts.discardAll()
            return true
        case .cancel:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

enum SettingsCloseQuestion {
    case discard
    case cancel

    static let answers: [SettingsCloseQuestion] = [
        .discard,
        .cancel,
    ]

    static func findAnswer(_ leftovers: [SettingsLeftover]) -> SettingsCloseQuestion {
        getAnswer(at: PromptWindow.ask(getPrompt(leftovers)))
    }

    static func getPrompt(_ leftovers: [SettingsLeftover]) -> HatPrompt {
        let lines = leftovers.map { "\($0.name) \($0.text): \($0.reason)" }

        return HatPrompt(
            title: "Some typed numbers were not applied",
            text: (lines + ["Discard them, or cancel and fix them."]).joined(separator: "\n"),
            buttons: answers.map(getTitle)
        )
    }

    static func getAnswer(at index: Int) -> SettingsCloseQuestion {
        guard answers.indices.contains(index) else { return .cancel }

        return answers[index]
    }

    private static func getTitle(_ answer: SettingsCloseQuestion) -> String {
        switch answer {
        case .discard: return "Discard"
        case .cancel: return "Cancel"
        }
    }
}
