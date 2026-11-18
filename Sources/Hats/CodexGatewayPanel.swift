import SwiftUI

struct CodexGatewayPanel: View {
    @ObservedObject var model: HatsModel
    @State private var portText = ""

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
            HStack(spacing: 8) {
                Text("Port").font(.system(size: 13))
                TextField(String(CodexGatewayPaths.defaultPort), text: $portText)
                    .frame(width: 70).textFieldStyle(.roundedBorder)
                Button("Apply") { applyTypedPort() }.disabled(applicablePort == nil)
            }
            .controlSize(.small)
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
        .onAppear { portText = String(snapshot.settings.codexGatewayPort) }
        .onChange(of: snapshot.settings.codexGatewayPort) { port in portText = String(port) }
    }

    private var isAProblem: Bool {
        if case .failed = face.status { return true }
        return face.configNote != nil
    }

    private var applicablePort: Int? {
        TypedNumber.applicable(
            portText,
            current: snapshot.settings.codexGatewayPort,
            isUsable: AppSettings.isAUsablePort
        )
    }

    private func applyTypedPort() {
        guard let port = applicablePort else { return }
        model.actions?.applyCodexGatewayPort(port)
    }
}
