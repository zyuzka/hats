import SwiftUI

final class SignInModel: ObservableObject {
    @Published var transcript = SignInTranscript()
    @Published var code = ""
    @Published var trouble: String?

    let title: String
    var submit: (String) -> Void = { _ in Journal.log("signIn.codeIgnored") }
    var stop: () -> Void = { Journal.log("signIn.stopIgnored") }

    init(title: String) { self.title = title }
}

struct SignInView: View {
    @ObservedObject var model: SignInModel
    @State private var showsTheOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.title)
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(HatsCopy.signInStage(model.transcript.stage))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = model.transcript.signInURL {
                Link("Open the sign-in page", destination: url).font(.system(size: 12))
            }
            if model.transcript.stage == .waitingForTheCode { codeEntry }
            if let trouble = model.trouble {
                Text(trouble)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            output
            HStack {
                Spacer()
                Button("Cancel") { model.stop() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private var codeEntry: some View {
        HStack(spacing: 8) {
            TextField("Code from the page", text: $model.code)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.submit(model.code) }
            Button("Sign in") { model.submit(model.code) }
                .keyboardShortcut(.defaultAction)
                .disabled(model.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var output: some View {
        DisclosureGroup("Output", isExpanded: $showsTheOutput) {
            ScrollView {
                Text(model.transcript.text.isEmpty ? "nothing yet" : model.transcript.text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 140)
        }
        .font(.system(size: 12))
    }
}
