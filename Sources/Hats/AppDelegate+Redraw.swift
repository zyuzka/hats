import AppKit

extension AppDelegate {
    func redraw() {
        var snapshot = HatsSnapshot(autoSwitchWarning: lastAutoSwitchWarning)
        snapshot.header = liveIdentity.display
        let somebodyLooks = popover.isShown || sessions.isVisible
        let chromeNames = somebodyLooks ? ChromeProfiles.names() : [:]
        snapshot.rows = ClaudeDoors.claudeRows(store.accounts, live: liveIdentity.email) { hat, isWearing in
            HatRowState(
                hat: hat,
                isWearing: isWearing,
                usage: usage.readings[hat.id],
                usageTrouble: usage.troubles[hat.id],
                roseWhileParked: usage.roseWhileParked[hat.id],
                week: weekly.memory.findSighting(of: hat.id, readings: usage.readings, fresh: usage.freshInTheLastPoll),
                chromeNames: chromeNames
            )
        }
        snapshot.codexRows = codexRows(chromeNames: chromeNames)
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
        snapshot.hasFullDiskAccess = FullDiskAccess.isGranted()
        snapshot.gatewaySessions = somebodyLooks ? GatewayProcess.sessionRows : popover.model.snapshot.gatewaySessions
        snapshot.environment = gatewayEnvironment
        snapshot.settings = settings
        snapshot.showTheBanners(of: settings)
        snapshot.codexAutoSwitchWarning = codexSwitch.lastWarning
        snapshot.version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        snapshot.canCheckForUpdates = updater?.canCheckNow
        snapshot.checksForUpdatesAutomatically = updater?.checksAutomatically
        snapshot.changing = changing
        snapshot.startAtLogin = LoginItem.currentFace
        snapshot.retiredPort = GatewayProcess.retiredPort
        snapshot.portRefusal = GatewayProcess.lastPortRefusal
        snapshot.reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        snapshot.sessionHandoff = handoff.row
        snapshot.showTheCodexPluginRow(of: codexPlugin)
        snapshot.contextRows = SessionWindow.getMenuRows(sessionWindows.windows, now: Date())
        syncTheCodexGatewayIfItsInputsMoved()
        snapshot.codexGateway = codexGatewayFace
        popover.model.snapshot = snapshot
        writeTheHatUsage()
        contextChannel.setThresholds(settings.contextThresholds, limits: settings.limitThresholds, at: Date())
        syncTheCodexWindow()

        if let blink {
            blink.show(snapshot.markState, blinking: settings.blinksTheCursorInTheMenuBar)
        } else {
            statusItem.button?.image = Mark.image(state: snapshot.markState)
        }
        statusItem.button?.title = snapshot.menuBarTitle
        statusItem.button?.setAccessibilityLabel(snapshot.menuBarAccessibilityLabel)
        let sighting = BannerSighting.of(popoverShown: popover.isShown,
                                         popoverClosing: popover.isClosing,
                                         hasBanner: snapshot.banner(on: settings.popoverTab) != nil)
        if sighting == .seen { markBannerSeen(on: settings.popoverTab) }
    }

    func showTheContextRows() {
        popover.model.snapshot.contextRows = SessionWindow.getMenuRows(sessionWindows.windows, now: Date())
    }

    private func markBannerSeen(on tool: Tool) {
        let key: WritableKeyPath<AppSettings, AutoSwitchRecord?> =
            tool == .codex ? \.codexAutoSwitchRecord : \.autoSwitchRecord
        guard var record = settings[keyPath: key], !record.seenInPopover else { return }
        record.seenInPopover = true
        settings[keyPath: key] = record
        saveSettings()
    }

    func saveSettings() {
        do {
            try settings.save()
        } catch {
            Journal.log("settings.notSaved", ["reason": error.localizedDescription])
        }
    }

    func rememberTheWeek() {
        let liveIDs = WeeklyRecord.findLiveIDs(store.accounts.map(\.id), indexIsUnusable: store.indexUnusable != nil)
        switch weekly.noteAPoll(usage.readings, fresh: usage.freshInTheLastPoll, liveIDs: liveIDs) {
        case .failed(let reason):
            guard lastWeeklyFailure.shouldWrite(reason) else { return }
            Journal.log("weekly.notSaved", ["reason": reason])
        case .written, .unchanged:
            lastWeeklyFailure.clear()
        case .heldBecauseTheHatsAreUnknown:
            break
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
            decideAutoSwitch(from: .aPollLanded)
        }
    }

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
