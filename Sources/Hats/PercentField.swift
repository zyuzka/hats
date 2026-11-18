import SwiftUI

struct PercentField<Leading: View>: View {
    let label: String
    let percent: Int?
    let bounds: PercentBounds
    let note: String?
    let apply: (Int) -> Void
    @ViewBuilder let leading: () -> Leading

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                leading()
                Spacer()
                if let percent {
                    field(percent)
                }
            }
            if let reason = state.reason {
                Text(reason).font(.system(size: 11)).foregroundStyle(Color.orange)
            }
        }
        .onAppear { text = percent.map(String.init) ?? "" }
        .onChange(of: percent) { now in text = now.map(String.init) ?? "" }
    }

    private func field(_ percent: Int) -> some View {
        HStack(spacing: 6) {
            TextField(String(percent), text: $text)
                .accessibilityLabel(label)
                .frame(width: 44)
                .textFieldStyle(.roundedBorder)
                .onSubmit { applyTyped() }
            Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            Stepper(
                "",
                value: Binding(
                    get: { percent },
                    set: { value in apply(bounds.getStepRange().getClamped(value)) }
                ),
                in: bounds.getStepRange(),
                step: 1
            )
            .labelsHidden()
            .accessibilityLabel(label)
            Button("Apply") { applyTyped() }.disabled(state.applicable == nil)
        }
        .controlSize(.small)
    }

    private var state: PercentFieldState {
        TypedNumber.getPercentFieldState(text, current: percent, bounds: bounds, note: note)
    }

    private func applyTyped() {
        guard let value = state.applicable else { return }
        apply(value)
    }
}
