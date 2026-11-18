import Foundation

protocol HatsActions: AnyObject {
    func wear(_ id: String)
    func addHat(for tool: Tool)
    func relogin(_ id: String)
    func rename(_ id: String)
    func chooseBrowser(_ id: String)
    func setVacation(_ id: String, on: Bool)
    func remove(_ id: String)
    func setGateway(enabled: Bool)
    func applyGatewayPort(_ port: Int)
    func applyGatewaySettle(_ seconds: Int)
    func restartGateway()
    func setCodexGateway(enabled: Bool)
    func applyCodexGatewayPort(_ port: Int)
    func takeOverProfile()
    func keepMyProfile()
    func copyVariables()
    func openLog()
    func updateAutoSwitch(_ policy: AutoSwitchPolicy)
    func updateContextThresholds(_ thresholds: ContextThresholds)
    func updateLimitThresholds(_ thresholds: LimitThresholds)
    func setUsageDisplay(_ display: UsageDisplay)
    func setPopoverTab(_ tool: Tool)
    func switchBack()
    func openSessions()
    func showSettings()
    func checkForUpdates()
    func toggleAutomaticUpdateChecks()
    func showReleases()
    func toggleStartAtLogin()
    func toggleHatNameInTheMenuBar()
    func toggleTheBlinkingCursor()
    func installSessionHandoff()
    func updateSessionHandoff()
    func removeSessionHandoff()
    func quit()
}

final class HatsModel: ObservableObject {
    @Published var snapshot = HatsSnapshot()
    weak var actions: HatsActions?
}
