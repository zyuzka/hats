import SwiftUI

struct PercentField<Leading: View>: View {
    let label: String
    let field: SettingsField
    let percent: Int?
    let stepRange: ClosedRange<Int>
    let note: String?
    @ObservedObject var model: HatsModel
    @ObservedObject var drafts: SettingsDrafts
    let step: (Int) -> Void
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                leading()
                Spacer()
                if let percent {
                    row(percent)
                }
            }
            if let reason = state.reason {
                Text(reason).font(.system(size: 11)).foregroundStyle(Color.orange)
            }
        }
    }

    private func row(_ percent: Int) -> some View {
        HStack(spacing: 6) {
            DigitField(
                text: state.text,
                placeholder: String(percent),
                label: label,
                change: { drafts.setText($0, of: field, in: model.snapshot.settings) },
                submit: { drafts.apply(field, model) },
                cancel: { drafts.reset(field) }
            )
            .frame(width: 44)
            Text("%").font(.system(size: 11)).foregroundStyle(.secondary)
            Stepper(
                "",
                value: Binding(
                    get: { percent },
                    set: { value in
                        step(stepRange.getClamped(value))
                        drafts.applyPartner(of: field, model)
                    }
                ),
                in: stepRange,
                step: 1
            )
            .labelsHidden()
            .accessibilityLabel(label)
        }
        .controlSize(.small)
    }

    private var state: SettingsFieldState {
        drafts.getState(field, in: model.snapshot.settings, note: note)
    }
}
