import SwiftUI

struct HatRowView: View {
    let row: HatRowState
    let isChanging: Bool
    let handover: String?
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
            Text(row.isWearing ? "✓" : " ").font(.system(size: 12, weight: .semibold)).frame(width: 12)
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

    @ViewBuilder private var detail: some View {
        if row.isWearing, let usage = row.usage {
            Text(HatsCopy.usageLine(usage)).font(.system(size: 11)).foregroundStyle(secondary)
            if let stale = HatsCopy.staleReading(row.usageTrouble) {
                Text(stale).font(.system(size: 11)).foregroundStyle(secondary)
            }
            if let handover { Text(handover).font(.system(size: 11)).foregroundStyle(secondary) }
        } else if row.isWearing, let trouble = row.usageTrouble {
            Text(trouble.onTheRow).font(.system(size: 11)).foregroundStyle(secondary)
        } else if !row.isWearing, let usage = row.usage,
                  let parked = HatsCopy.parkedUsage(usage, rose: row.roseWhileParked) {
            Text(parked).font(.system(size: 11)).foregroundStyle(secondary)
            if let stale = HatsCopy.staleReading(row.usageTrouble) {
                Text(stale).font(.system(size: 11)).foregroundStyle(secondary)
            }
        } else if let trouble = row.usageTrouble {
            Text(trouble.onTheRow).font(.system(size: 11)).foregroundStyle(secondary)
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
        .padding(.leading, 28).padding(.trailing, 8).padding(.bottom, 6)
    }

    private func tapped() {
        if row.isWearing || isChanging { return }
        if row.isSwitchable { onWear() } else { showsBlocker.toggle() }
    }
}
