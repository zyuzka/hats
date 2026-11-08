import AppKit
import Sparkle

final class SparkleUpdates: NSObject, AppUpdater, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    var whenCanCheckNowChanges: (() -> Void)?

    private let decideTheRestart: () -> GatewayStopDecision
    private var controller: SPUStandardUpdaterController?
    private var canCheckWatch: NSKeyValueObservation?
    private lazy var gate = UpdateInstallGate(
        decideTheRestart: decideTheRestart,
        confirm: { HatDialogs.hasConfirmedInstallingTheUpdate(cost: $0) },
        notify: { Notifier.post(title: $0, body: $1) },
        beforeAsking: { [weak self] ask in
            DispatchQueue.main.async {
                self?.controller?.userDriver.dismissUpdateInstallation()
                ask()
            }
        }
    )

    private init(decideTheRestart: @escaping () -> GatewayStopDecision) {
        self.decideTheRestart = decideTheRestart
    }

    static func createIfConfigured(
        info: [String: Any]? = Bundle.main.infoDictionary,
        decideTheRestart: @escaping () -> GatewayStopDecision
    ) -> SparkleUpdates? {
        guard AppUpdates.isTheBundleConfigured(info) else {
            Journal.log("update.notConfigured")
            return nil
        }

        return SparkleUpdates(decideTheRestart: decideTheRestart)
    }

    var canCheckNow: Bool { controller?.updater.canCheckForUpdates ?? false }

    func start() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        canCheckWatch = controller.updater.observe(
            \.canCheckForUpdates,
            options: [
                .new,
            ]
        ) { [weak self] _, _ in
            DispatchQueue.main.async { self?.whenCanCheckNowChanges?() }
        }
        self.controller = controller
    }

    func checkNow() {
        if gate.hasAnInstallWaiting {
            gate.askAboutTheWaitingInstall()
            return
        }
        DockPresence.aWindowIsAboutToOpen()
        controller?.checkForUpdates(nil)
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        gate.shouldPostponeTheRestart(version: item.displayVersionString, install: installHandler)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        gate.forgetTheWaitingInstall()
        let failure = error as NSError
        guard failure.code != Int(SUError.noUpdateError.rawValue) else { return }
        Journal.log("update.failed", [
            "code": String(failure.code),
            "reason": failure.localizedDescription,
        ])
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        DockPresence.aWindowIsAboutToOpen()
        Journal.log("update.found", [
            "version": update.displayVersionString,
            "userInitiated": String(state.userInitiated),
        ])
        guard !state.userInitiated else { return }
        gate.announceOnce(version: update.displayVersionString)
    }

    func standardUserDriverWillFinishUpdateSession() {
        DispatchQueue.main.async { DockPresence.refresh() }
    }
}
