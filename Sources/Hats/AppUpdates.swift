import Foundation

protocol AppUpdater: AnyObject {
    var canCheckNow: Bool { get }
    var checksAutomatically: Bool { get set }
    var hasAnUpdateWaiting: Bool { get }
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

    static func toggleAutomaticChecks(of updater: AppUpdater, log: (String, [String: String]) -> Void) {
        updater.checksAutomatically.toggle()
        log("update.automaticChecks", [
            "enabled": String(updater.checksAutomatically),
        ])
    }
}

extension GatewayStopDecision {
    static func getForAnUpdate(
        ports: [Int],
        sessions: @autoclosure () -> [Session]?,
        codexThreads: Int = 0
    ) -> GatewayStopDecision {
        let costs = [
            HatsCopy.getUpdateInstallCost(ports: ports, sessions: sessions()),
            HatsCopy.codexQuitCost(threads: codexThreads),
        ].compactMap { $0 }
        guard !costs.isEmpty else { return .proceed }

        return .ask(costs.joined(separator: " "))
    }
}

final class UpdateInstallGate {
    private let decideTheRestart: () -> GatewayStopDecision
    private let confirm: (String) -> Bool
    private let notify: (_ title: String, _ body: String) -> Void
    private let beforeAsking: (@escaping () -> Void) -> Void
    private let waitingChanged: () -> Void
    private var installWaitingForQuit: (() -> Void)?
    private var waitingVersion = ""
    private var announcedVersion: String?
    private var session = 0

    init(
        decideTheRestart: @escaping () -> GatewayStopDecision,
        confirm: @escaping (String) -> Bool,
        notify: @escaping (_ title: String, _ body: String) -> Void,
        beforeAsking: @escaping (@escaping () -> Void) -> Void,
        waitingChanged: @escaping () -> Void
    ) {
        self.decideTheRestart = decideTheRestart
        self.confirm = confirm
        self.notify = notify
        self.beforeAsking = beforeAsking
        self.waitingChanged = waitingChanged
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
        let asked = session
        beforeAsking { [weak self] in self?.ask(cost, version: version, install: install, in: asked) }

        return true
    }

    func askAboutTheWaitingInstall() {
        guard let install = installWaitingForQuit else { return }
        var cost = HatsCopy.updateWaitsForQuit
        if case .ask(let named) = decideTheRestart() { cost = named }
        ask(cost, version: waitingVersion, install: install, in: session)
    }

    func forgetTheWaitingInstall() {
        session += 1
        let wasWaiting = hasAnInstallWaiting
        installWaitingForQuit = nil
        waitingVersion = ""
        if wasWaiting { waitingChanged() }
    }

    func announceOnce(version: String) {
        guard announcedVersion != version else { return }
        announcedVersion = version
        notify("Hats \(version) is out", "Install it from the update window.")
    }

    private func ask(_ cost: String, version: String, install: @escaping () -> Void, in asked: Int) {
        guard !hasTheSessionEnded(asked, version: version) else { return }
        let isConfirmed = confirm(cost)
        guard !hasTheSessionEnded(asked, version: version) else { return }
        guard isConfirmed else {
            installWaitingForQuit = install
            waitingVersion = version
            Journal.log("update.installOnQuit", [
                "version": version,
            ])
            waitingChanged()
            return
        }
        forgetTheWaitingInstall()
        Journal.log("update.installing", [
            "version": version,
        ])
        install()
    }

    private func hasTheSessionEnded(_ asked: Int, version: String) -> Bool {
        guard asked != session else { return false }
        Journal.log("update.sessionEnded", [
            "version": version,
        ])

        return true
    }
}
