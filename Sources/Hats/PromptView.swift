import SwiftUI

struct HatPrompt: Equatable {
    let title: String
    let text: String
    let buttons: [String]
}

struct PromptView: View {
    let prompt: HatPrompt
    let choose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.title)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !prompt.text.isEmpty {
                Text(prompt.text)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
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
    }

    @ViewBuilder private func action(_ index: Int, _ title: String) -> some View {
        let button = Button(title) { choose(index) }
        if PromptButtons.isDefault(index, of: prompt.buttons.count) {
            button.keyboardShortcut(.defaultAction)
        } else if PromptButtons.isCancel(index, of: prompt.buttons.count) {
            button.keyboardShortcut(.cancelAction)
        } else {
            button
        }
    }
}
