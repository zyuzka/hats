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

    func updateLimitThresholds(_ thresholds: LimitThresholds) {
        settings.limitThresholds = thresholds
        saveSettings()
        redraw()
    }
}
