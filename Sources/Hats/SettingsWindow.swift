import AppKit
import SwiftUI

struct SettingsTabs: View {
    @ObservedObject var model: HatsModel
    @ObservedObject var drafts: SettingsDrafts

    var body: some View {
        VStack(spacing: 10) {
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
            HStack {
                Spacer()
                Button("Apply") { drafts.apply(model) }
                    .disabled(!drafts.canApply(in: model.snapshot.settings))
            }
        }
        .padding(14)
        .frame(width: 460, height: 456)
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
        guard let model else { return true }
        let settings = model.snapshot.settings
        guard drafts.hasPending(in: settings) else { return true }
        let canApply = drafts.canApply(in: settings)
        switch SettingsCloseQuestion.findAnswer(canApply: canApply) {
        case .apply:
            drafts.apply(model)
            return !drafts.hasPending(in: model.snapshot.settings)
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
    case apply
    case discard
    case cancel

    static func findAnswer(canApply: Bool) -> SettingsCloseQuestion {
        let answers = getAnswers(canApply: canApply)
        let index = PromptWindow.ask(HatPrompt(
            title: canApply ? "Apply the typed numbers?" : "Some typed numbers cannot be applied",
            text: canApply
                ? "The window has numbers that were typed but not applied."
                : "Discard all typed numbers, or cancel and fix the refused ones.",
            buttons: answers.map(getTitle)
        ))

        return getAnswer(at: index, among: answers)
    }

    static func getAnswers(canApply: Bool) -> [SettingsCloseQuestion] {
        guard canApply else {
            return [
                .discard,
                .cancel,
            ]
        }

        return [
            .apply,
            .discard,
            .cancel,
        ]
    }

    static func getAnswer(at index: Int, among answers: [SettingsCloseQuestion]) -> SettingsCloseQuestion {
        guard answers.indices.contains(index) else { return .cancel }

        return answers[index]
    }

    private static func getTitle(_ answer: SettingsCloseQuestion) -> String {
        switch answer {
        case .apply: return "Apply"
        case .discard: return "Discard"
        case .cancel: return "Cancel"
        }
    }
}
