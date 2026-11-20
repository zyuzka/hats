import SwiftUI

struct HatListView: View {
    @ObservedObject var model: HatsModel

    var snapshot: HatsSnapshot { model.snapshot }

    private var tab: Tool { snapshot.settings.popoverTab }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 4)
            if !snapshot.hasFullDiskAccess { fullDiskAccessView }
            if let banner = snapshot.banner(on: tab) {
                bannerView(banner.record, fromTitle: banner.fromTitle, of: banner.tool)
            }
            if let stranded = snapshot.deadEndBanner(on: tab, now: Date()) { strandedView(stranded) }
            tabPicker
            let rows = snapshot.rows(of: tab)
            if rows.isEmpty { noHats } else { list(rows) }
            if tab == .claudeCode, !snapshot.contextRows.isEmpty { context }
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
                Text(snapshot.headerTitle(on: tab)).font(.system(size: 17, weight: .semibold))
                if let wearing = snapshot.wearing(on: tab), wearing.title != wearing.address {
                    Text(wearing.address).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private var tabPicker: some View {
        Picker("Provider", selection: Binding(
            get: { tab },
            set: { model.actions?.setPopoverTab($0) }
        )) {
            ForEach(Tool.allCases, id: \.self) { tool in
                Text(HatsCopy.tab(tool, averages: ProviderSummary.of(snapshot.rows(of: tool), now: Date())))
                    .monospacedDigit()
                    .tag(tool)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14).padding(.bottom, 6)
    }

    private func list(_ rows: [HatRowState]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(HatsCopy.providerAverage(ProviderSummary.of(rows, now: Date())))
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 2).padding(.top, 2)
            ForEach(rows) { row in
                HatRowView(
                    row: row,
                    isChanging: snapshot.changing == row.id,
                    handover: snapshot.getHandover(for: row),
                    display: snapshot.settings.usageDisplay,
                    tool: row.tool,
                    onWear: { model.actions?.wear(row.id) },
                    onRelogin: { model.actions?.relogin(row.id) }
                )
            }
        }
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(HatsCopy.contextHeader).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary).padding(.bottom, 2)
            ForEach(snapshot.contextRows) { row in
                HStack {
                    Text(row.label).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(row.value).monospacedDigit()
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.top, 6)
    }

    private var noHats: some View {
        VStack(spacing: 6) {
            Text(HatsCopy.noHats(on: tab)).font(.system(size: 13, weight: .semibold))
            Text(HatsCopy.noHatsHint(on: tab))
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
                footerButton("plus", help: "Add hat…") { model.actions?.addHat(for: tab) }
                    .keyboardShortcut("n", modifiers: .command)
                footerButton("gearshape.fill", help: "Settings…") { model.actions?.showSettings() }
                footerButton("power", help: "Quit Hats") { model.actions?.quit() }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(.horizontal, 14)
    }
}
