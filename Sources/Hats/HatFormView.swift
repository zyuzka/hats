import SwiftUI

final class HatFormState: ObservableObject {
    @Published var name = ""
    @Published var email = ""
    @Published var browser: BrowserChoice?
}

struct HatFormFields: OptionSet {
    let rawValue: Int

    static let name = HatFormFields(rawValue: 1 << 0)
    static let email = HatFormFields(rawValue: 1 << 1)
    static let browser = HatFormFields(rawValue: 1 << 2)
}

struct HatFormView: View {
    let prompt: HatPrompt
    let fields: HatFormFields
    let namePlaceholder: String
    let choices: [BrowserChoice]
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
            if fields.contains(.name) {
                TextField(namePlaceholder, text: $state.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
            }
            if fields.contains(.email) {
                TextField("email address", text: $state.email).textFieldStyle(.roundedBorder)
            }
            if fields.contains(.browser) { browsers }
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

    private var browsers: some View {
        Picker("", selection: $state.browser) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                Text(choice.label(chromeNames: chromeNames)).tag(BrowserChoice?.some(choice))
            }
        }
        .labelsHidden()
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
