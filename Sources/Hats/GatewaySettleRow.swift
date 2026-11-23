import SwiftUI

struct GatewaySettleRow: View {
    @ObservedObject var model: HatsModel
    @ObservedObject var drafts: SettingsDrafts

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(HatsCopy.settleLabel).font(.system(size: 13))
                DigitField(
                    text: state.text,
                    placeholder: "35",
                    label: HatsCopy.settleLabel,
                    change: { drafts.setText($0, of: .settle, in: model.snapshot.settings) },
                    submit: { drafts.apply(.settle, model) },
                    cancel: { drafts.reset(.settle) }
                )
                .frame(width: 50)
                Text("s").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            if let warning = state.reason ?? HatsCopy.settleWarning(settleSeconds: typedOrCurrent) {
                Text(warning).font(.system(size: 11)).foregroundStyle(Color.orange)
            }
        }
        .padding(.horizontal, 14)
    }

    private var state: SettingsFieldState {
        drafts.getState(.settle, in: model.snapshot.settings)
    }

    private var typedOrCurrent: Int {
        TypedNumber.typed(state.text) ?? model.snapshot.settings.gatewaySettleSeconds
    }
}
