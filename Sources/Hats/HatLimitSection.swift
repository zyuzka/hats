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
                range: limits.getWarnRange(),
                toggle: { next, isOn in next.setWarn(isOn: isOn) },
                step: { next, percent in next.setWarn(percent) }
            )
            limitThreshold(
                HatsCopy.anchorAt,
                percent: limits.savePercent,
                range: limits.getSaveRange(),
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
        range: ClosedRange<Int>,
        toggle: @escaping (inout LimitThresholds, Bool) -> Void,
        step: @escaping (inout LimitThresholds, Int) -> Void
    ) -> some View {
        HStack {
            Toggle(label, isOn: Binding(
                get: { percent != nil },
                set: { isOn in changeLimits { toggle(&$0, isOn) } }
            ))
            .font(.system(size: 13))
            Spacer()
            if let percent {
                Stepper(
                    "\(percent)%",
                    value: Binding(
                        get: { percent },
                        set: { value in changeLimits { step(&$0, value) } }
                    ),
                    in: range,
                    step: 1
                )
                .font(.system(size: 13))
            }
        }
    }
}
