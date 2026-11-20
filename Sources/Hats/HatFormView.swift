import AppKit
import SwiftUI

final class HatFormState: ObservableObject {
    @Published var name = ""
    @Published var email = ""
    @Published var browser: BrowserChoice?
    @Published var tool: Tool

    init(tool: Tool = .claudeCode) {
        self.tool = tool
    }
}

struct HatFormFields: OptionSet {
    let rawValue: Int

    static let name = HatFormFields(rawValue: 1 << 0)
    static let email = HatFormFields(rawValue: 1 << 1)
    static let browser = HatFormFields(rawValue: 1 << 2)
    static let provider = HatFormFields(rawValue: 1 << 3)
}

struct HatFormView: View {
    let prompt: HatPrompt
    let fields: HatFormFields
    let namePlaceholder: String
    let choices: [BrowserChoice]
    let browserWarning: String?
    let chromeNames: [String: String]
    @ObservedObject var state: HatFormState
    let choose: (Int) -> Void
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.title)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(prompt.text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            if fields.contains(.provider) { providers }
            if fields.contains(.name) {
                TextField(namePlaceholder, text: $state.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
            }
            if fields.contains(.email) {
                TextField("email address", text: $state.email).textFieldStyle(.roundedBorder)
            }
            if fields.contains(.browser) { browsers }
            if fields.contains(.browser), let browserWarning { warning(browserWarning) }
            HStack(spacing: 8) {
                Spacer()
                ForEach(PromptButtons.leftToRight(prompt.buttons), id: \.index) { button in
                    action(button.index, button.title)
                }
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(width: 380, alignment: .leading)
        .onAppear { typing = true }
    }

    private var providers: some View {
        Picker("", selection: $state.tool) {
            ForEach(Tool.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var browsers: some View {
        Picker("", selection: $state.browser) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                Text(choice.label(chromeNames: chromeNames)).tag(BrowserChoice?.some(choice))
            }
        }
        .labelsHidden()
    }

    private func warning(_ text: String) -> some View {
        Button {
            if let url = BrowserChoice.fullDiskAccessSettings { NSWorkspace.shared.open(url) }
        } label: {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func action(_ index: Int, _ title: String) -> some View {
        let button = Button(title) { choose(index) }
        if PromptButtons.isDefault(index, of: prompt.buttons.count) {
            button.keyboardShortcut(.defaultAction).disabled(!mayGoOn)
        } else if PromptButtons.isCancel(index, of: prompt.buttons.count) {
            button.keyboardShortcut(.cancelAction)
        } else {
            button
        }
    }

    private var mayGoOn: Bool {
        guard fields.contains(.email) else { return true }
        return HatFormRules.canAdd(email: state.email, browser: state.browser)
    }
}
