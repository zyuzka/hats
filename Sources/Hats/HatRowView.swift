import SwiftUI

struct HatRowView: View {
    let row: HatRowState
    let isChanging: Bool
    let handover: String?
    let display: UsageDisplay
    let tool: Tool
    let onWear: () -> Void
    let onRelogin: () -> Void

    @State private var hovering = false
    @State private var showsBlocker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            main
            if showsBlocker, let blocker = row.blocker { blockerRow(blocker) }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering && row.isSwitchable && !row.isWearing ? Color.accentColor : Color.clear)
        )
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture(perform: tapped)
    }

    private var lit: Bool { hovering && row.isSwitchable && !row.isWearing }

    private var main: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            wornMark
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.title).font(.system(size: 13, weight: row.isWearing ? .semibold : .regular))
                    if row.title != row.address {
                        Text(row.address).font(.system(size: 11)).foregroundStyle(secondary)
                    }
                }
                detail
            }
            Spacer(minLength: 8)
            trailing
        }
        .foregroundStyle(lit ? Color.white : Color.primary)
        .padding(.vertical, 6).padding(.horizontal, 8)
    }

    private var secondary: Color { lit ? Color.white.opacity(0.85) : .secondary }

    @ViewBuilder private var wornMark: some View {
        switch RowMark.of(row, tool: tool) {
        case .hat(let tool):
            HatMarkView(tool: tool)
        case .blank:
            Color.clear.frame(width: HatMark.rowWidth, height: 1)
        }
    }

    private var detail: some View {
        let lines = RowDetail.lines(of: row, display: display, handover: handover)
        return ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            switch line {
            case .text(let text):
                Text(text).font(.system(size: 11)).foregroundStyle(secondary)
            case .bar(let bar):
                UsageBarView(bar: bar, secondary: secondary, lit: lit)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if isChanging {
            Text("changing…").font(.system(size: 11)).foregroundStyle(secondary)
        } else if row.isWearing {
            Text("On now").font(.system(size: 11)).foregroundStyle(secondary)
        } else if let blocker = row.blocker {
            Text(blocker).font(.system(size: 11)).foregroundStyle(Color.orange)
        } else if lit {
            Text("click to wear").font(.system(size: 11)).foregroundStyle(secondary)
        } else if let expiry = row.expiry {
            Text(expiry).font(.system(size: 11)).foregroundStyle(Color.orange)
        }
    }

    private func blockerRow(_ blocker: String) -> some View {
        HStack {
            Text(HatsCopy.cannotWear(blocker)).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button(row.loginAction, action: onRelogin).controlSize(.small)
        }
        .padding(.leading, 30).padding(.trailing, 8).padding(.bottom, 6)
    }

    private func tapped() {
        if row.isWearing || isChanging { return }
        if row.isSwitchable { onWear() } else { showsBlocker.toggle() }
    }
}
