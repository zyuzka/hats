import SwiftUI

struct HatLimitSection: View {
    @ObservedObject var model: HatsModel

    private var limits: LimitThresholds { model.snapshot.settings.limitThresholds }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(HatsCopy.hatLimit)
                .font(.system(size: 13, weight: .semibold))
            limitThreshold(
                HatsCopy.warnAt,
                percent: limits.warnPercent,
                bounds: limits.getWarnBounds(),
                note: limits.canTurnWarnOn() ? nil : limits.savePercent.map {
                    HatsCopy.getNoRoomBelow(HatsCopy.anchorAt, percent: $0)
                },
                toggle: { next, isOn in next.setWarn(isOn: isOn) },
                step: { next, percent in next.setWarn(percent) }
            )
            limitThreshold(
                HatsCopy.anchorAt,
                percent: limits.savePercent,
                bounds: limits.getSaveBounds(),
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
        percent: Int?,
        bounds: PercentBounds,
        note: String?,
        toggle: @escaping (inout LimitThresholds, Bool) -> Void,
        step: @escaping (inout LimitThresholds, Int) -> Void
    ) -> some View {
        PercentField(
            label: label,
            percent: percent,
            bounds: bounds,
            note: percent == nil ? note : nil,
            apply: { value in changeLimits { step(&$0, value) } },
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
