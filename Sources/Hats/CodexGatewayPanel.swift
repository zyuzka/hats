import SwiftUI

struct CodexGatewayPanel: View {
    @ObservedObject var model: HatsModel
    @ObservedObject var drafts: SettingsDrafts

    private var snapshot: HatsSnapshot { model.snapshot }
    private var face: CodexGatewayFace { snapshot.codexGateway }
    private var isOn: Bool {
        CodexGatewayWanted.isWanted(hasCodexHats: face.hasCodexHats, enabled: snapshot.settings.isCodexGatewayEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: Binding(
                    get: { isOn },
                    set: { model.actions?.setCodexGateway(enabled: $0) }
                )) { Text("Run the Codex gateway").font(.system(size: 13)) }
                .toggleStyle(.switch)
                .disabled(!face.hasCodexHats)
                Text(HatsCopy.codexGatewayRunDetail(face.status, hasCodexHats: face.hasCodexHats))
                    .font(.system(size: 11))
                    .foregroundStyle(isAProblem ? Color.orange : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Port").font(.system(size: 13))
                    DigitField(
                        text: portState.text,
                        placeholder: String(CodexGatewayPaths.defaultPort),
                        label: "Codex gateway port",
                        change: { drafts.setText($0, of: .codexPort, in: snapshot.settings) },
                        submit: { drafts.apply(model) },
                        cancel: { drafts.reset(.codexPort) }
                    )
                    .frame(width: 70)
                }
                .controlSize(.small)
                if let reason = portState.reason {
                    Text(reason).font(.system(size: 11)).foregroundStyle(Color.orange)
                }
            }
            if let note = face.configNote {
                Text(note).font(.system(size: 11)).foregroundStyle(Color.orange)
            }
            if face.status.isServing {
                Text(HatsCopy.codexThreadsLine(face.threads)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            Text(HatsCopy.codexGatewayLimits).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
    }

    private var isAProblem: Bool {
        if case .failed = face.status { return true }
        return face.configNote != nil
    }

    private var portState: SettingsFieldState { drafts.getState(.codexPort, in: snapshot.settings) }
}
