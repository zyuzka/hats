import SwiftUI

struct GeneralPanel: View {
    @ObservedObject var model: HatsModel

    private var snapshot: HatsSnapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            menuBarRows
            Divider()
            startAtLoginRow
            Divider()
            versionRow
            Spacer()
        }
        .padding(.vertical, 14)
    }

    private var menuBarRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { snapshot.settings.showsHatNameInTheMenuBar },
                set: { _ in model.actions?.toggleHatNameInTheMenuBar() }
            )) { Text("Show hat name in the menu bar").font(.system(size: 13)) }
            .toggleStyle(.switch)
            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: Binding(
                    get: { snapshot.settings.blinksTheCursorInTheMenuBar },
                    set: { _ in model.actions?.toggleTheBlinkingCursor() }
                )) { Text("Blink the cursor").font(.system(size: 13)) }
                .toggleStyle(.switch)
                if snapshot.reducesMotion {
                    Text("the cursor stays steady while Reduce Motion is on in System Settings")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private var startAtLoginRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(
                get: { snapshot.startAtLogin.state == .on },
                set: { _ in model.actions?.toggleStartAtLogin() }
            )) { Text(snapshot.startAtLogin.title).font(.system(size: 13)) }
            .toggleStyle(.switch)
            .disabled(!snapshot.startAtLogin.isEnabled)
            if snapshot.startAtLogin.state == .mixed {
                Text("macOS is waiting for you to allow it in System Settings › General › Login Items")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
    }

    private var versionRow: some View {
        HStack {
            Button("Version \(snapshot.version)") { model.actions?.showReleases() }
                .buttonStyle(.link)
                .help("What changed in this and every earlier version")
            Spacer()
            Button(HatsCopy.updateButton(waiting: snapshot.updateWaiting)) {
                model.actions?.checkForUpdates()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
    }
}
