import SwiftUI

struct ContextThresholdsPanel: View {
    @ObservedObject var model: HatsModel
    @ObservedObject var drafts: SettingsDrafts

    private var thresholds: ContextThresholds { model.snapshot.settings.contextThresholds }

    var body: some View {
        ScrollView {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            threshold(
                HatsCopy.warnAt,
                field: .contextWarn,
                percent: thresholds.warnPercent,
                stepRange: thresholds.getWarnRange(),
                toggle: { next, isOn in next.setWarn(isOn: isOn) },
                step: { next, percent in next.setWarn(percent) }
            )
            drain
            threshold(
                HatsCopy.anchorAt,
                field: .contextSave,
                percent: thresholds.savePercent,
                stepRange: thresholds.getSaveRange(),
                toggle: { next, isOn in next.setSave(isOn: isOn) },
                step: { next, percent in next.setSave(percent) }
            )
            afterAnchoring
            Text(HatsCopy.contextThresholdsNote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HatLimitSection(model: model, drafts: drafts)
            codexContinue
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
        field: SettingsField,
        percent: Int?,
        stepRange: ClosedRange<Int>,
        toggle: @escaping (inout ContextThresholds, Bool) -> Void,
        step: @escaping (inout ContextThresholds, Int) -> Void
    ) -> some View {
        PercentField(
            label: label,
            field: field,
            percent: percent,
            stepRange: stepRange,
            note: nil,
            model: model,
            drafts: drafts,
            step: { value in change { step(&$0, value) } },
            leading: {
                Toggle(label, isOn: Binding(
                    get: { percent != nil },
                    set: { isOn in change { toggle(&$0, isOn) } }
                ))
                .font(.system(size: 13))
            }
        )
    }

    private var drain: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(HatsCopy.drainBackgroundWork, isOn: Binding(
                    get: { thresholds.drain },
                    set: { isOn in change { $0.drain = isOn } }
                ))
                .font(.system(size: 13))
                Spacer()
                if thresholds.drain {
                    Stepper(
                        HatsCopy.getDrainWaitTitle(minutes: thresholds.drainMinutes),
                        value: Binding(
                            get: { thresholds.drainMinutes },
                            set: { minutes in change { $0.setDrainMinutes(minutes) } }
                        ),
                        in: ContextThresholds.drainMinutesRange,
                        step: 1
                    )
                    .font(.system(size: 13))
                }
            }
            .disabled(!thresholds.canDrain(limits: model.snapshot.settings.limitThresholds))
            Text(HatsCopy.drainNote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var codexContinue: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(HatsCopy.continueCodex, isOn: Binding(
                get: { model.snapshot.settings.continuesCodexAfterCompaction },
                set: { isOn in model.actions?.setCodexContinue(isOn) }
            ))
            .font(.system(size: 13))
            .disabled(thresholds.savePercent == nil || thresholds.warnPercent == nil)
            if thresholds.savePercent == nil || thresholds.warnPercent == nil {
                Text(HatsCopy.continueCodexNeedsThresholds)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(HatsCopy.continueCodexNote)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
