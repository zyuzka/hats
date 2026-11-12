import SwiftUI

struct SessionHandoffRow: Equatable {
    var face: SessionHandoffFace = .unread
    var isBusy = false
}

struct SessionHandoffRowView: View {
    let row: SessionHandoffRow
    let install: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Session handoff").font(.system(size: 13))
                Spacer()
                if row.isBusy {
                    ProgressView().controlSize(.small)
                }
                if row.face.canInstall {
                    Button("Install\u{2026}", action: install)
                        .controlSize(.small)
                        .disabled(row.isBusy)
                }
                if row.face.canRemove {
                    Button("Remove\u{2026}", action: remove)
                        .controlSize(.small)
                        .disabled(row.isBusy)
                }
            }
            Text(SessionHandoffCopy.getStatus(row.face))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help("A Claude Code plugin that saves a resume note on the anchor command and hands it to the next "
            + "session. Hats installs and removes it with claude plugin, and only when you agree.")
        .padding(.horizontal, 14)
    }
}
