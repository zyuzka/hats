import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AccountStore()
    let popover = HatsPopover()
    let sessions = LiveSessionsWindow()
    let releases = ReleasesWindow()
    let settingsWindow = SettingsWindow()
    let usage = AutoSwitchWatch()
    lazy var login = LoginFlow(store: store)

    var statusItem: NSStatusItem!
    var blink: MarkBlink?
    var liveIdentity: LiveIdentity = .unreadable
    var settings = AppSettings.loaded()
    var lastSyncFailure: String?
    var lastAutoSwitchHold: AutoSwitchHold?
    var gatewayEnvironment: GatewayEnvironmentReport?
    var changing: String?
    var lookAtTheProcessTable: [Session]??
    var updateWaiting: String?
    let updates = UpdateWatch()

    func withOneLookAtTheProcessTable(_ body: () -> Void) {
        guard lookAtTheProcessTable == nil, wantsTheProcessTable else {
            body()
            return
        }
        lookAtTheProcessTable = .some(SessionDiscovery.everySessionSeenRecently())
        defer { lookAtTheProcessTable = nil }
        body()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        EditMenu.install()
        QuitOnSignal.install()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(markClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let blink = MarkBlink(button: statusItem.button)
        blink.watchTheSystem()
        self.blink = blink

        if settings.autoSwitch.wantsNotifications { Notifier.askOnce() }

        GatewayProcess.port = settings.gatewayPort
        startOrStopTheGateway()

        popover.model.actions = self
        popover.willShow = { [weak self] in
            self?.withOneLookAtTheProcessTable {
                self?.releaseTheRetiredListenerIfNothingNeedsIt()
                self?.syncWithWorld(reportingErrors: false)
                self?.decideAutoSwitch()
            }
        }
        login.liveLoginMoved = { [weak self] identity in self?.redraw(ifTheLiveLoginMoved: identity) }
        login.syncWithWorld = { [weak self] reporting, claim in
            self?.syncWithWorld(reportingErrors: reporting, claiming: claim)
        }
        login.lastTrouble = { [weak self] in self?.lastSyncFailure }
        login.signInSettled = { [weak self] in
            guard let self else { return }
            Journal.log("usage.pollAfterASignIn")
            usage.poll(hatsForUsage())
        }

        usage.onAuthObservation = { [weak self] refused, accepted in
            self?.store.noteAuthObservation(refused: refused, accepted: accepted)
        }
        usage.onRenewals = { [weak self] renewals in self?.store.noteRenewed(renewals) }
        usage.onReadings = { [weak self] _ in self?.redrawAndDecide() }
        usage.start(hats: { [weak self] in self?.hatsForUsage() ?? [] })
        watchForUpdates()

        redraw()
        DispatchQueue.main.async { [weak self] in self?.syncWithWorld() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        usage.stop()
        blink?.stop()
        GatewayProcess.stop()
        gatewayEnvironment = GatewayEnvironment.ensure(serving: false)
    }

    @objc private func markClicked() {
        guard let button = statusItem.button else { return }
        switch MarkClick.of(NSApp.currentEvent) {
        case .menu:
            showSettings()
        case .popover:
            popover.toggle(relativeTo: button)
        }
    }

    func hatsForUsage() -> [(id: String, isWearing: Bool)] {
        let live = liveIdentity.email
        return store.accounts.map { hat in
            (hat.id, live.map { Account.sameAddress(hat.email, $0) } ?? false)
        }
    }

    @discardableResult
    func syncWithWorld(reportingErrors: Bool = true, claiming claim: CredentialClaim? = nil) -> String? {
        let claim = claim ?? .forSync(duty: login.duty())
        let identity = store.liveIdentity()
        liveIdentity = identity
        var reconciled: String?
        do {
            let outcome = try store.reconcileWithLiveLogin(observing: identity, claiming: claim)
            store.pruneOrphanedCredentials()
            if case .reconciled(let account, _) = outcome { reconciled = account }
            noteSyncTrouble(outcome.unsettledReason, shownToTheUser: false)
        } catch {
            noteSyncTrouble(error.localizedDescription, shownToTheUser: reportingErrors)
            if reportingErrors { HatDialogs.present(error, title: "Could not read the accounts") }
        }
        redraw()
        return reconciled
    }

    private func noteSyncTrouble(_ reason: String?, shownToTheUser: Bool) {
        guard let reason else {
            lastSyncFailure = nil
            return
        }
        guard reason != lastSyncFailure else { return }
        Journal.log("sync.unsettled", ["reason": reason, "shownToTheUser": String(shownToTheUser)])
        lastSyncFailure = reason
    }

    func redraw(ifTheLiveLoginMoved identity: LiveIdentity) {
        guard !popover.isShown, identity.isASettledChange(from: liveIdentity) else { return }
        liveIdentity = identity
        redraw()
    }

    func redrawAfterTheLiveSlotMayHaveMoved() {
        liveIdentity = store.liveIdentity()
        redraw()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
