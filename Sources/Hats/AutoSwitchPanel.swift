import SwiftUI

struct AutoSwitchPanel: View {
    @ObservedObject var model: HatsModel
    @ObservedObject var drafts: SettingsDrafts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                AutoSwitchBlock(
                    tool: .claudeCode,
                    policy: model.snapshot.settings.autoSwitch,
                    rows: model.snapshot.rows,
                    fields: (session: .sessionSwitch, weekly: .weeklySwitch),
                    model: model,
                    drafts: drafts,
                    update: { model.actions?.updateAutoSwitch($0) }
                )
                Text(HatsCopy.whenSessionsChangeHats(
                    settleSeconds: model.snapshot.settings.gatewaySettleSeconds
                ))
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 14)
                Divider().padding(.horizontal, 14)
                AutoSwitchBlock(
                    tool: .codex,
                    policy: model.snapshot.settings.codexAutoSwitch,
                    rows: model.snapshot.codexRows,
                    fields: (session: .codexSessionSwitch, weekly: .codexWeeklySwitch),
                    model: model,
                    drafts: drafts,
                    update: { model.actions?.updateCodexAutoSwitch($0) }
                )
            }
            .padding(.vertical, 8)
        }
    }
}
