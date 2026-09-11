import SwiftUI

struct AutoSwitchPanel: View {
    @ObservedObject var model: HatsModel

    private var policy: AutoSwitchPolicy { model.snapshot.settings.autoSwitch }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.snapshot.tool.displayName).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary).padding(.horizontal, 14)
            Toggle(isOn: binding(\.isOn)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Change hat when a limit is reached").font(.system(size: 13))
                    Text("puts on the next hat that still has room, in the order below")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).padding(.horizontal, 14)
            triggers
            order
            Toggle("Notify me when it changes", isOn: binding(\.notifies))
                .font(.system(size: 12)).padding(.horizontal, 14)
            Text(HatsCopy.whenSessionsChangeHats(
                settleSeconds: model.snapshot.settings.gatewaySettleSeconds
            ))
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 14)
        }
        .padding(.vertical, 8)
    }

    private func binding<T>(_ key: WritableKeyPath<AutoSwitchPolicy, T>) -> Binding<T> {
        Binding(
            get: { policy[keyPath: key] },
            set: { value in
                var next = policy
                next[keyPath: key] = value
                model.actions?.updateAutoSwitch(next)
            }
        )
    }

    private var triggers: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trigger on").font(.system(size: 11)).foregroundStyle(.secondary)
            threshold("the 5-hour limit", \.sessionThresholdPercent, fallback: 90)
            threshold("the weekly limit", \.weeklyThresholdPercent, fallback: 95)
        }
        .padding(.horizontal, 14)
    }

    private func threshold(
        _ label: String,
        _ key: WritableKeyPath<AutoSwitchPolicy, Int?>,
        fallback: Int
    ) -> some View {
        HStack {
            Toggle(label, isOn: Binding(
                get: { policy[keyPath: key] != nil },
                set: { on in
                    var next = policy
                    next[keyPath: key] = on ? fallback : nil
                    model.actions?.updateAutoSwitch(next)
                }
            )).font(.system(size: 12))
            Spacer()
            if let percent = policy[keyPath: key] {
                Stepper(
                    "at \(percent)%",
                    value: Binding(
                        get: { percent },
                        set: { value in
                            var next = policy
                            next[keyPath: key] = min(100, max(50, value))
                            model.actions?.updateAutoSwitch(next)
                        }
                    ),
                    in: 50...100,
                    step: 5
                )
                .font(.system(size: 12))
            }
        }
    }

    private var order: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Order").font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(Array(orderedRows.enumerated()), id: \.element.id) { index, row in
                HStack {
                    Text(row.isWearing ? "—" : "\(index + 1)").frame(width: 16).foregroundStyle(.secondary)
                    Text(row.title).font(.system(size: 12))
                    if row.isWearing { Text("worn now").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Spacer()
                    if !row.isWearing {
                        Button("↑") { move(row.id, by: -1) }.disabled(index == 0)
                        Button("↓") { move(row.id, by: 1) }.disabled(index >= movableCount - 1)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
    }

    private var movableCount: Int { orderedRows.filter { !$0.isWearing }.count }

    private var orderedRows: [HatRowState] {
        let rows = model.snapshot.rows
        let ordered = policy.order.compactMap { id in rows.first { $0.id == id && !$0.isWearing } }
        let rest = rows.filter { row in !row.isWearing && !policy.order.contains(row.id) }
        return ordered + rest + rows.filter(\.isWearing)
    }

    private func move(_ id: String, by delta: Int) {
        var ids = orderedRows.filter { !$0.isWearing }.map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        let target = index + delta
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        var next = policy
        next.order = ids
        model.actions?.updateAutoSwitch(next)
    }
}
