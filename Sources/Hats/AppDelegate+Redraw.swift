import AppKit

extension AppDelegate {
    func redraw() {
        var snapshot = HatsSnapshot()
        snapshot.header = liveIdentity.display
        let somebodyLooks = popover.isShown || sessions.isVisible
        let chromeNames = somebodyLooks ? ChromeProfiles.names() : [:]
        snapshot.rows = store.accounts.map { hat in
            HatRowState(
                hat: hat,
                isWearing: liveIdentity.email.map { Account.sameAddress(hat.email, $0) } ?? false,
                usage: usage.readings[hat.id],
                usageTrouble: usage.troubles[hat.id],
                roseWhileParked: usage.roseWhileParked[hat.id],
                chromeNames: chromeNames
            )
        }
        let taken: [Session]?? = lookAtTheProcessTable ?? (somebodyLooks
            ? .some(SessionDiscovery.everySessionSeenRecently())
            : nil)
        if let taken {
            snapshot.everySession = taken
            snapshot.sessions = taken.map { SessionsState.counted($0.filter(\.isInteractive)) } ?? .unknown
        } else {
            snapshot.everySession = popover.model.snapshot.everySession
            snapshot.sessions = popover.model.snapshot.sessions
        }
        snapshot.horizon = SessionHorizon.line(soonestParkedAccessExpiry: store.soonestParkedAccessExpiry)
        snapshot.gateway = GatewayProcess.status
        snapshot.gatewaySessions = somebodyLooks ? GatewayProcess.sessionRows : popover.model.snapshot.gatewaySessions
        snapshot.environment = gatewayEnvironment
        snapshot.settings = settings
        snapshot.banner = settings.autoSwitchRecord.flatMap { $0.seenInPopover ? nil : $0 }
        snapshot.bannerFromTitle = settings.autoSwitchRecord.map { snapshot.title(of: $0.from) } ?? ""
        snapshot.version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        snapshot.updateWaiting = updateWaiting
        snapshot.changing = changing
        snapshot.startAtLogin = LoginItem.currentFace
        snapshot.retiredPort = GatewayProcess.retiredPort
        snapshot.portRefusal = GatewayProcess.lastPortRefusal
        snapshot.reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.model.snapshot = snapshot

        if let blink {
            blink.show(markState(snapshot), blinking: settings.blinksTheCursorInTheMenuBar)
        } else {
            statusItem.button?.image = Mark.image(state: markState(snapshot))
        }
        statusItem.button?.title = snapshot.menuBarTitle
        statusItem.button?.setAccessibilityLabel(snapshot.menuBarAccessibilityLabel)
        let sighting = BannerSighting.of(popoverShown: popover.isShown,
                                         popoverClosing: popover.isClosing,
                                         hasBanner: snapshot.banner != nil)
        if sighting == .seen { markBannerSeen() }
    }

    private func markState(_ snapshot: HatsSnapshot) -> MarkState {
        MarkState.decide(
            anyHatBlocked: snapshot.rows.contains { $0.blocker != nil },
            gatewayEnabled: settings.isGatewayEnabled,
            gatewayServing: snapshot.gateway.isServing,
            wearing: snapshot.wearing != nil,
            percent: snapshot.wearing?.usage?.session?.percent
        )
    }

    private func markBannerSeen() {
        guard var record = settings.autoSwitchRecord, !record.seenInPopover else { return }
        record.seenInPopover = true
        settings.autoSwitchRecord = record
        saveSettings()
    }

    func saveSettings() {
        do {
            try settings.save()
        } catch {
            Journal.log("settings.notSaved", ["reason": error.localizedDescription])
        }
    }

    func startOrStopTheGateway() {
        guard settings.isGatewayEnabled else {
            GatewayProcess.stop()
            gatewayEnvironment = GatewayEnvironment.ensure(serving: false)
            return
        }
        let status = GatewayProcess.restart(on: settings.gatewayPort, settle: settleWanted)
        gatewayEnvironment = GatewayEnvironment.ensure(serving: status.isServing)
    }

    func redrawAndDecide() {
        withOneLookAtTheProcessTable {
            redraw()
            releaseTheRetiredListenerIfNothingNeedsIt()
            decideAutoSwitch()
        }
    }

    var settleWanted: TimeInterval { TimeInterval(settings.gatewaySettleSeconds) }

    var wantsTheProcessTable: Bool {
        GatewayProcess.hasARetiredListener || popover.isShown || sessions.isVisible
    }

    func releaseTheRetiredListenerIfNothingNeedsIt() {
        guard GatewayProcess.hasARetiredListener else { return }
        let live: [Session]? = lookAtTheProcessTable ?? SessionDiscovery.everySessionSeenRecently()
        let verdict = GatewayRetirement.verdict(
            hasRetired: true,
            retiredPort: GatewayProcess.retiredPort,
            sessions: live
        )
        guard verdict == .releaseIt else { return }
        GatewayProcess.closeTheRetiredListener()
        redraw()
    }
}
