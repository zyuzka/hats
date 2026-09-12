import SwiftUI

struct GatewayPanel: View {
    @ObservedObject var model: HatsModel
    @State private var portText = ""

    private var snapshot: HatsSnapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            runRow
            portRow
            GatewaySettleRow(seconds: snapshot.settings.gatewaySettleSeconds) {
                model.actions?.applyGatewaySettle($0)
            }
            profileRow
            Divider()
            HStack(spacing: 8) {
                if snapshot.settings.isGatewayEnabled {
                    Button("Restart gateway") { model.actions?.restartGateway() }
                }
                Button("Copy variables") { model.actions?.copyVariables() }
            }
            .controlSize(.small).padding(.horizontal, 14)
        }
        .padding(.vertical, 8)
        .onAppear { portText = String(snapshot.settings.gatewayPort) }
        .onChange(of: snapshot.settings.gatewayPort) { port in portText = String(port) }
    }

    private var runRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(
                get: { snapshot.settings.isGatewayEnabled },
                set: { model.actions?.setGateway(enabled: $0) }
            )) { Text("Run the gateway").font(.system(size: 13)) }
            .toggleStyle(.switch)
            Text(runDetail).font(.system(size: 11))
                .foregroundStyle(snapshot.gateway.isServing ? .secondary : Color.orange)
        }
        .padding(.horizontal, 14)
    }

    private var runDetail: String {
        HatsCopy.gatewayRunDetail(snapshot.gateway, settleSeconds: snapshot.settings.gatewaySettleSeconds)
    }

    private var portRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("Port").font(.system(size: 13))
                TextField("8787", text: $portText).frame(width: 70).textFieldStyle(.roundedBorder)
                Button("Apply") { applyTypedPort() }.disabled(!isTypedPortApplicable)
                if isAPortWorthWalkingPast, AppSettings.isAUsablePort(nextPortToTry) {
                    Button("Try \(nextPortToTry)") { walkToTheNextPort() }
                }
            }
            .controlSize(.small)
            if let refusal = snapshot.portRefusal {
                Text("the port did not change: \(refusal)").font(.system(size: 11))
                    .foregroundStyle(Color.orange)
            }
            if let retired = snapshot.retiredPort {
                Text(HatsCopy.retiredListener(
                    port: retired,
                    dependants: snapshot.sessionsThrough(port: retired),
                    keptByTheTypedPort: typedPort == retired
                ))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
    }

    private var typedPort: Int? { TypedNumber.typed(portText) }

    private var applicablePort: Int? {
        TypedNumber.applicable(
            portText,
            current: snapshot.settings.gatewayPort,
            isUsable: AppSettings.isAUsablePort
        )
    }

    private var isAPortWorthWalkingPast: Bool {
        if snapshot.portRefusal != nil { return true }
        if case .failed = snapshot.gateway { return true }
        return false
    }

    private var nextPortToTry: Int { (typedPort ?? snapshot.settings.gatewayPort) + 1 }

    private func walkToTheNextPort() {
        let next = nextPortToTry
        portText = String(next)
        model.actions?.applyGatewayPort(next)
    }

    private var isTypedPortApplicable: Bool { applicablePort != nil }

    private func applyTypedPort() {
        guard let port = applicablePort else { return }
        model.actions?.applyGatewayPort(port)
    }

    @ViewBuilder private var profileRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add the variables to my shell profile").font(.system(size: 13))
            if let report = snapshot.environment {
                Text(profileDetail(report)).font(.system(size: 11))
                    .foregroundStyle(isAWarning(report) ? Color.orange : .secondary)
                if case .foreign = report.verdict, snapshot.settings.foreignProfileResolution == .undecided,
                   snapshot.gateway.isServing {
                    HStack(spacing: 8) {
                        Button("Use the gateway instead") { model.actions?.takeOverProfile() }
                        Button("Keep mine") { model.actions?.keepMyProfile() }
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func isAWarning(_ report: GatewayEnvironmentReport) -> Bool {
        report.isWarning && snapshot.settings.foreignProfileResolution == .undecided
    }

    private func profileDetail(_ report: GatewayEnvironmentReport) -> String {
        if let line = report.menuLine { return line }
        return (report.profilePath ?? "profile")
            + " · shells opened from now on send their sessions through the gateway"
    }
}
