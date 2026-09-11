import SwiftUI

struct GatewaySettleRow: View {
    let seconds: Int
    let apply: (Int) -> Void

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("Settle").font(.system(size: 13))
                TextField("35", text: $text).frame(width: 50).textFieldStyle(.roundedBorder)
                Text("s").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Apply") { applyTyped() }.disabled(!isTypedApplicable)
            }
            .controlSize(.small)
            if let warning = HatsCopy.settleWarning(settleSeconds: typedOrCurrent) {
                Text(warning).font(.system(size: 11)).foregroundStyle(Color.orange)
            }
        }
        .padding(.horizontal, 14)
        .onAppear { text = String(seconds) }
        .onChange(of: seconds) { now in text = String(now) }
    }

    private var typed: Int? {
        TypedNumber.applicable(text, current: seconds, isUsable: AppSettings.isAUsableSettle)
    }

    private var typedOrCurrent: Int {
        TypedNumber.typed(text) ?? seconds
    }

    private var isTypedApplicable: Bool { typed != nil }

    private func applyTyped() {
        guard let value = typed else { return }
        apply(value)
    }
}
