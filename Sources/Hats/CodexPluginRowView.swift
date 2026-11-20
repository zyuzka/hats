import SwiftUI

struct CodexPluginRow: Equatable {
    var face: CodexPluginFace = .unread
    var isBusy = false
    var offer: SessionHandoffOffer?
}

struct CodexPluginRowView: View {
    let row: CodexPluginRow
    let install: () -> Void
    let update: () -> Void
    let refresh: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Codex plugin").font(.system(size: 13))
                Spacer()
                if row.isBusy {
                    ProgressView().controlSize(.small)
                }
                buttons
            }
            if let line = CodexPluginText.getUpdateLine(row) {
                Text(line.text)
                    .font(.system(size: 11))
                    .accessibilityLabel(line.spoken)
            }
            Text(CodexPluginText.getStatus(row.face))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help("A Codex plugin that saves a resume note before Codex compacts the context window and hands it "
            + "back after. Hats installs, updates and removes it with codex plugin, and only when you agree.")
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var buttons: some View {
        if row.face.canInstall {
            Button("Install\u{2026}", action: install).controlSize(.small).disabled(row.isBusy)
        }
        if row.offer != nil {
            Button("Update\u{2026}", action: update).controlSize(.small).disabled(row.isBusy)
        }
        if row.face.canRefresh {
            Button("Refresh\u{2026}", action: refresh).controlSize(.small).disabled(row.isBusy)
        }
        if row.face.canRemove {
            Button("Remove\u{2026}", action: remove).controlSize(.small).disabled(row.isBusy)
        }
    }
}
