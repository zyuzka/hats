import Foundation

extension AppDelegate {
    func updateContextThresholds(_ thresholds: ContextThresholds) {
        settings.contextThresholds = thresholds
        saveSettings()
        redraw()
    }
}
