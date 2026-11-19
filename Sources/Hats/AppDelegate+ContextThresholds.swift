import Foundation

extension AppDelegate {
    func startTheContextChannel() {
        contextChannel.hatTitle = { [weak self] id in self?.popover.model.snapshot.title(of: id) ?? id }
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
