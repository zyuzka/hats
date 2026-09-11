import SwiftUI

struct HatListView: View {
    @ObservedObject var model: HatsModel

    private var snapshot: HatsSnapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 4)
            if let banner = snapshot.banner { bannerView(banner) }
            if snapshot.rows.isEmpty { empty } else { list }
            Divider().padding(.vertical, 4)
            footer
        }
        .padding(.vertical, 8)
        .frame(width: 340)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Wearing now").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(snapshot.wearing?.title ?? snapshot.header).font(.system(size: 17, weight: .semibold))
                if let wearing = snapshot.wearing, wearing.title != wearing.address {
                    Text(wearing.address).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.tool.displayName).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 2)
            ForEach(snapshot.rows) { row in
                HatRowView(
                    row: row,
                    isChanging: snapshot.changing == row.id,
                    handover: handover(for: row),
                    onWear: { model.actions?.wear(row.id) },
                    onRelogin: { model.actions?.relogin(row.id) }
                )
            }
        }
    }

    private func handover(for row: HatRowState) -> String? {
        guard row.isWearing, snapshot.settings.autoSwitch.isOn, let next = snapshot.nextInLine else { return nil }
        return HatsCopy.handover(to: snapshot.title(of: next))
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("No hats yet").font(.system(size: 13, weight: .semibold))
            Text("Name an account — Work, Personal, Team — and Hats keeps its login ready to put on.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 20)
    }

    private func footerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.actions?.openSessions()
            } label: {
                HStack {
                    Text(HatsCopy.sessions(
                        snapshot.sessions,
                        wearing: snapshot.wearing?.title,
                        gatewayBaseURLs: snapshot.gatewayAddresses.all,
                        serving: snapshot.gateway.isServing
                    ))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("›").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .focusable(false)
            HStack {
                Text(HatsCopy.gateway(snapshot.gateway)).font(.system(size: 11))
                    .foregroundStyle(snapshot.gateway.isServing ? .secondary : Color.orange)
                Spacer()
                footerButton("plus", help: "Add hat…") { model.actions?.addHat() }
                    .keyboardShortcut("n", modifiers: .command)
                footerButton("gearshape.fill", help: "Settings…") { model.actions?.showSettings() }
                footerButton("power", help: "Quit Hats") { model.actions?.quit() }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(.horizontal, 14)
    }

    private func bannerView(_ record: AutoSwitchRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(HatsCopy.banner(record, fromTitle: snapshot.bannerFromTitle)).font(.system(size: 11))
            Button("Switch back now") { model.actions?.switchBack() }.controlSize(.small)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 10).padding(.bottom, 6)
    }
}
