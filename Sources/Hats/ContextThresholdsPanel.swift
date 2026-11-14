import SwiftUI

struct ContextThresholdsPanel: View {
    @ObservedObject var model: HatsModel

    private var thresholds: ContextThresholds { model.snapshot.settings.contextThresholds }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            threshold(
                HatsCopy.warnAt,
                percent: thresholds.warnPercent,
                range: thresholds.getWarnRange(),
                toggle: { next, isOn in next.setWarn(isOn: isOn) },
                step: { next, percent in next.setWarn(percent) }
            )
            threshold(
                HatsCopy.anchorAt,
                percent: thresholds.savePercent,
                range: thresholds.getSaveRange(),
                toggle: { next, isOn in next.setSave(isOn: isOn) },
                step: { next, percent in next.setSave(percent) }
            )
            afterAnchoring
            Text(HatsCopy.contextThresholdsNote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private func change(_ body: (inout ContextThresholds) -> Void) {
        var next = thresholds
        body(&next)
        model.actions?.updateContextThresholds(next)
    }

    private func threshold(
        _ label: String,
        percent: Int?,
        range: ClosedRange<Int>,
        toggle: @escaping (inout ContextThresholds, Bool) -> Void,
        step: @escaping (inout ContextThresholds, Int) -> Void
    ) -> some View {
        HStack {
            Toggle(label, isOn: Binding(
                get: { percent != nil },
                set: { isOn in change { toggle(&$0, isOn) } }
            ))
            .font(.system(size: 13))
            Spacer()
            if let percent {
                Stepper(
                    "\(percent)%",
                    value: Binding(
                        get: { percent },
                        set: { value in change { step(&$0, value) } }
                    ),
                    in: range,
                    step: 1
                )
                .font(.system(size: 13))
            }
        }
    }

    private var afterAnchoring: some View {
        Picker(HatsCopy.afterAnchoring, selection: Binding(
            get: { thresholds.afterSave },
            set: { action in change { $0.afterSave = action } }
        )) {
            ForEach(AfterSave.allCases, id: \.self) { action in
                Text(HatsCopy.getAfterSaveTitle(action)).tag(action)
            }
        }
        .pickerStyle(.radioGroup)
        .font(.system(size: 13))
        .disabled(thresholds.savePercent == nil)
    }
}
