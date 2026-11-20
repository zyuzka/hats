@testable import Hats

final class RecordingActions: HatsActions {
    private(set) var calls: [String] = []
    private let model: HatsModel
    private let isPortMoved: Bool

    init(model: HatsModel, isPortMoved: Bool) {
        self.model = model
        self.isPortMoved = isPortMoved
    }

    func applyGatewayPort(_ port: Int) {
        calls.append("port \(port)")
        guard isPortMoved else { return }
        model.snapshot.settings.gatewayPort = port
    }

    func applyGatewaySettle(_ seconds: Int) {
        calls.append("settle \(seconds)")
        model.snapshot.settings.gatewaySettleSeconds = seconds
    }

    func updateAutoSwitch(_ policy: AutoSwitchPolicy) {
        calls.append("autoSwitch \(policy.sessionThresholdPercent ?? 0) \(policy.weeklyThresholdPercent ?? 0)")
        model.snapshot.settings.autoSwitch = policy
    }

    func updateContextThresholds(_ thresholds: ContextThresholds) {
        calls.append("context \(thresholds.warnPercent ?? 0) \(thresholds.savePercent ?? 0)")
        model.snapshot.settings.contextThresholds = thresholds
    }

    func updateLimitThresholds(_ thresholds: LimitThresholds) {
        calls.append("limits \(thresholds.warnPercent ?? 0) \(thresholds.savePercent ?? 0)")
        model.snapshot.settings.limitThresholds = thresholds
    }

    func wear(_ id: String) {}
    func addHat() {}
    func relogin(_ id: String) {}
    func rename(_ id: String) {}
    func chooseBrowser(_ id: String) {}
    func remove(_ id: String) {}
    func setVacation(_ id: String, on: Bool) {}
    func setGateway(enabled: Bool) {}
    func restartGateway() {}
    func takeOverProfile() {}
    func keepMyProfile() {}
    func copyVariables() {}
    func openLog() {}
    func switchBack() {}
    func openSessions() {}
    func showSettings() {}
    func checkForUpdates() {}
    func toggleAutomaticUpdateChecks() {}
    func showReleases() {}
    func toggleStartAtLogin() {}
    func toggleHatNameInTheMenuBar() {}
    func toggleTheBlinkingCursor() {}
    func installSessionHandoff() {}
    func updateSessionHandoff() {}
    func removeSessionHandoff() {}
    func quit() {}
}
