import Foundation

extension AppDelegate {
    func startTheContextChannel() {
        contextChannel.hatTitle = { [weak self] id in self?.popover.model.snapshot.title(of: id) ?? id }
        contextChannel.onStagesRead = { [weak self] in self?.writeTheHatUsage() }
        contextChannel.start { [weak self] in self?.sessionWindows.windows ?? [] }
    }

    func updateContextThresholds(_ thresholds: ContextThresholds) {
        settings.contextThresholds = thresholds
        saveSettings()
        redraw()
    }

    func updateLimitThresholds(_ thresholds: LimitThresholds) {
        settings.limitThresholds = thresholds
        saveSettings()
        redraw()
    }
}
