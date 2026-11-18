import SwiftUI

struct GatewaysPanel: View {
    @ObservedObject var model: HatsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                title(Tool.claudeCode)
                GatewayPanel(model: model)
                Divider().padding(.horizontal, 14).padding(.vertical, 6)
                title(Tool.codex)
                CodexGatewayPanel(model: model)
            }
            .padding(.vertical, 8)
        }
    }

    private func title(_ tool: Tool) -> some View {
        Text(tool.displayName).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 2)
    }
}
