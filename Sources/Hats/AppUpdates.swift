import Foundation

protocol AppUpdater: AnyObject {
    var canCheckNow: Bool { get }
    var checksAutomatically: Bool { get set }
    var whenCanCheckNowChanges: (() -> Void)? { get set }
    func start()
    func checkNow()
}

enum AppUpdates {
    static let feedKey = "SUFeedURL"
    static let publicKeyKey = "SUPublicEDKey"

    static func isTheBundleConfigured(_ info: [String: Any]?) -> Bool {
        let feed = (info?[feedKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = (info?[publicKeyKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return !feed.isEmpty && !key.isEmpty
    }
}

extension GatewayStopDecision {
    static func getForAnUpdate(ports: [Int], sessions: @autoclosure () -> [Session]?) -> GatewayStopDecision {
        guard let cost = HatsCopy.getUpdateInstallCost(ports: ports, sessions: sessions()) else {
            return .proceed
        }

        return .ask(cost)
    }
}

final class UpdateInstallGate {
    private let decideTheRestart: () -> GatewayStopDecision
    private let confirm: (String) -> Bool
    private let notify: (_ title: String, _ body: String) -> Void
    private let beforeAsking: (@escaping () -> Void) -> Void
    private var installWaitingForQuit: (() -> Void)?
    private var waitingVersion = ""
    private var announcedVersion: String?

    init(
        decideTheRestart: @escaping () -> GatewayStopDecision,
        confirm: @escaping (String) -> Bool,
        notify: @escaping (_ title: String, _ body: String) -> Void,
        beforeAsking: @escaping (@escaping () -> Void) -> Void
    ) {
        self.decideTheRestart = decideTheRestart
        self.confirm = confirm
        self.notify = notify
        self.beforeAsking = beforeAsking
    }

    var hasAnInstallWaiting: Bool { installWaitingForQuit != nil }

    func shouldPostponeTheRestart(version: String, install: @escaping () -> Void) -> Bool {
        guard case .ask(let cost) = decideTheRestart() else {
            Journal.log("update.installing", [
                "version": version,
            ])
            return false
        }
        Journal.log("update.askingBeforeRestart", [
            "version": version,
        ])
        beforeAsking { [weak self] in self?.ask(cost, version: version, install: install) }

        return true
    }

    func askAboutTheWaitingInstall() {
        guard let install = installWaitingForQuit else { return }
        var cost = HatsCopy.updateWaitsForQuit
        if case .ask(let named) = decideTheRestart() { cost = named }
        ask(cost, version: waitingVersion, install: install)
    }

    func forgetTheWaitingInstall() {
        installWaitingForQuit = nil
        waitingVersion = ""
    }

    func announceOnce(version: String) {
        guard announcedVersion != version else { return }
        announcedVersion = version
        notify("Hats \(version) is out", "Install it from the update window.")
    }

    private func ask(_ cost: String, version: String, install: @escaping () -> Void) {
        guard confirm(cost) else {
            installWaitingForQuit = install
            waitingVersion = version
            Journal.log("update.installOnQuit", [
                "version": version,
            ])
            return
        }
        forgetTheWaitingInstall()
        Journal.log("update.installing", [
            "version": version,
        ])
        install()
    }
}
