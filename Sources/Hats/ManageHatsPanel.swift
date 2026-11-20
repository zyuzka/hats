import SwiftUI

struct ManageHatsPanel: View {
    @ObservedObject var model: HatsModel
    @State var open: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section(.claudeCode)
                Divider().padding(.horizontal, 14).padding(.vertical, 6)
                section(.codex)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 340)
    }

    private func section(_ tool: Tool) -> some View {
        let rows = model.snapshot.rows(of: tool)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(tool.displayName).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Add…") { model.actions?.addHat(for: tool) }.controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.bottom, 6)
            ForEach(rows) { row in
                hatEntry(row)
            }
            if rows.isEmpty {
                Text(HatsCopy.noHats(on: tool)).font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
    }

    private var everyRow: [HatRowState] { model.snapshot.rows + model.snapshot.codexRows }

    private func hatEntry(_ row: HatRowState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                open = open == row.id ? nil : row.id
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).font(.system(size: 13, weight: row.isWearing ? .semibold : .regular))
                            .foregroundColor(row.isOnVacation ? Color(nsColor: ProviderColors.vacation) : nil)
                        Text(subtitle(row)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let blocker = row.blocker {
                        Text(blocker).font(.system(size: 11)).foregroundStyle(Color.orange)
                    }
                    Text(open == row.id ? "⌄" : "›").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open == row.id { actions(row) }
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
    }

    private func subtitle(_ row: HatRowState) -> String {
        var parts: [String] = []
        if row.title != row.address { parts.append(row.address) }
        if row.isWearing { parts.append("worn now") }
        if row.isOnVacation { parts.append(HatsCopy.vacationMark) }
        if let browser = row.browser { parts.append("opens in \(browser)") }
        if let validity = row.loginValidity { parts.append(validity) }
        return parts.joined(separator: " · ")
    }

    private func actions(_ row: HatRowState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let trouble = row.identityTrouble {
                Text(trouble)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons(row)
            createVacationRow(row)
        }
        .padding(.top, 2)
    }

    private func createVacationRow(_ row: HatRowState) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Toggle("On vacation", isOn: Binding(
                get: { row.isOnVacation },
                set: { model.actions?.setVacation(row.id, on: $0) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            Text(HatsCopy.vacationExplained)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func buttons(_ row: HatRowState) -> some View {
        HStack(spacing: 8) {
            Button(row.loginAction) { model.actions?.relogin(row.id) }
            Button("Rename…") { model.actions?.rename(row.id) }
            Button("Browser…") { model.actions?.chooseBrowser(row.id) }
            Spacer()
            Button("Remove") { model.actions?.remove(row.id) }
                .disabled(row.isWearing || everyRow.filter { $0.tool == row.tool }.count < 2)
        }
        .controlSize(.small)
    }
}
