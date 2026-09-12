import SwiftUI

struct ManageHatsPanel: View {
    @ObservedObject var model: HatsModel
    @State var open: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("Add…") { model.actions?.addHat() }.controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.bottom, 6)
            ForEach(model.snapshot.rows) { row in
                hatEntry(row)
            }
            if model.snapshot.rows.isEmpty {
                Text("No hats yet").font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 340)
    }

    private func hatEntry(_ row: HatRowState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                open = open == row.id ? nil : row.id
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).font(.system(size: 13, weight: row.isWearing ? .semibold : .regular))
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
        }
        .padding(.top, 2)
    }

    private func buttons(_ row: HatRowState) -> some View {
        HStack(spacing: 8) {
            Button(row.loginAction) { model.actions?.relogin(row.id) }
            Button("Rename…") { model.actions?.rename(row.id) }
            Button("Browser…") { model.actions?.chooseBrowser(row.id) }
            Spacer()
            Button("Remove") { model.actions?.remove(row.id) }
                .disabled(row.isWearing || model.snapshot.rows.count < 2)
        }
        .controlSize(.small)
    }
}
