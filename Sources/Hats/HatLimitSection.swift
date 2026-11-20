import SwiftUI

struct HatLimitSection: View {
    @ObservedObject var model: HatsModel
    @ObservedObject var drafts: SettingsDrafts

    private var limits: LimitThresholds { model.snapshot.settings.limitThresholds }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(HatsCopy.hatLimit)
                .font(.system(size: 13, weight: .semibold))
            limitThreshold(
                HatsCopy.warnAt,
                field: .limitWarn,
                percent: limits.warnPercent,
                stepRange: limits.getWarnRange(),
                note: limits.canTurnWarnOn() ? nil : limits.savePercent.map {
                    HatsCopy.getNoRoomBelow(HatsCopy.anchorAt, percent: $0)
                },
                toggle: { next, isOn in next.setWarn(isOn: isOn) },
                step: { next, percent in next.setWarn(percent) }
            )
            limitThreshold(
                HatsCopy.anchorAt,
                field: .limitSave,
                percent: limits.savePercent,
                stepRange: limits.getSaveRange(),
                note: limits.canTurnSaveOn() ? nil : limits.warnPercent.map {
                    HatsCopy.getNoRoomAbove(HatsCopy.warnAt, percent: $0)
                },
                toggle: { next, isOn in next.setSave(isOn: isOn) },
                step: { next, percent in next.setSave(percent) }
            )
            Text(HatsCopy.limitThresholdsNote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private func changeLimits(_ body: (inout LimitThresholds) -> Void) {
        var next = limits
        body(&next)
        model.actions?.updateLimitThresholds(next)
    }

    private func limitThreshold(
        _ label: String,
        field: SettingsField,
        percent: Int?,
        stepRange: ClosedRange<Int>,
        note: String?,
        toggle: @escaping (inout LimitThresholds, Bool) -> Void,
        step: @escaping (inout LimitThresholds, Int) -> Void
    ) -> some View {
        PercentField(
            label: label,
            field: field,
            percent: percent,
            stepRange: stepRange,
            note: percent == nil ? note : nil,
            model: model,
            drafts: drafts,
            step: { value in changeLimits { step(&$0, value) } },
            leading: {
                Toggle(label, isOn: Binding(
                    get: { percent != nil },
                    set: { isOn in changeLimits { toggle(&$0, isOn) } }
                ))
                .font(.system(size: 13))
                .disabled(percent == nil && note != nil)
            }
        )
    }
}
