import Foundation

extension AppDelegate {
    func startTheContextChannel() {
        contextChannel.setWiring(
            snapshot: { [weak self] in self?.popover.model.snapshot },
            stagesRead: { [weak self] in self?.writeTheHatUsage() }
        )
        contextChannel.start { [weak self] in self?.sessionWindows.windows ?? [] }
    }

    func updateContextThresholds(_ thresholds: ContextThresholds) {
        settings.contextThresholds = thresholds
        saveSettings()
        redraw()
    }

    func syncTheCodexWindow() {
        codexCompact.sync(savePercent: settings.contextThresholds.savePercent)
        codexContinue.configure(CodexContinueRun.Wish(
            isOn: settings.continuesCodexAfterCompaction,
            warnPercent: settings.contextThresholds.warnPercent,
            savePercent: settings.contextThresholds.savePercent
        ))
    }

    func setCodexContinue(_ isOn: Bool) {
        guard settings.continuesCodexAfterCompaction != isOn else { return }
        settings.continuesCodexAfterCompaction = isOn
        saveSettings()
        redraw()
    }

    func updateLimitThresholds(_ thresholds: LimitThresholds) {
        settings.limitThresholds = thresholds
        saveSettings()
        redraw()
    }
}
