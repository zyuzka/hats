import AppKit

extension AppDelegate {
    func openSessions() {
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self else { return }
            self.sessions.show(model: self.popover.model)
        }
    }

    func showSettings() {
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self else { return }
            self.settingsWindow.show(model: self.popover.model)
            self.handoff.refresh(then: nil)
            self.codexPlugin.refresh(then: nil)
        }
    }

    func toggleStartAtLogin() {
        do {
            Journal.log(try LoginItem.perform(LoginItem.currentFace.action))
        } catch {
            Journal.log("loginItem.failed", ["reason": error.localizedDescription])
            HatDialogs.present(error, title: "Could not change the login item")
        }
        redraw()
    }

    func toggleHatNameInTheMenuBar() {
        settings.showsHatNameInTheMenuBar.toggle()
        saveSettings()
        redraw()
    }

    func toggleTheBlinkingCursor() {
        settings.blinksTheCursorInTheMenuBar.toggle()
        saveSettings()
        redraw()
    }

    func setUsageDisplay(_ display: UsageDisplay) {
        guard settings.usageDisplay != display else { return }
        settings.usageDisplay = display
        saveSettings()
        redraw()
    }

    func setPopoverTab(_ tool: Tool) {
        guard settings.popoverTab != tool else { return }
        settings.popoverTab = tool
        saveSettings()
        redraw()
    }

    func showReleases() {
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self else { return }
            self.releases.show(running: self.popover.model.snapshot.version)
        }
    }

    func startTheUpdater() {
        updater = SparkleUpdates.createIfConfigured { [weak self] in
            GatewayStopDecision.getForAnUpdate(
                ports: GatewayProcess.heldPorts,
                sessions: SessionDiscovery.everySessionSeenRecently(),
                codexThreads: self?.codexThreadsThroughTheGateway ?? 0
            )
        }
        updater?.whenCanCheckNowChanges = { [weak self] in self?.redraw() }
        updater?.start()
    }

    func checkForUpdates() {
        popover.close()
        afterThePopoverSettles { [weak self] in self?.updater?.checkNow() }
    }

    func toggleAutomaticUpdateChecks() {
        guard let updater else { return }
        AppUpdates.toggleAutomaticChecks(of: updater) { Journal.log($0, $1) }
        redraw()
    }

    var codexThreadsThroughTheGateway: Int {
        codex.gateway.isServing ? codex.gateway.state.threadIDs.count : 0
    }

    func quit() {
        let live = SessionDiscovery.everySessionSeenRecently()
        let threads = codexThreadsThroughTheGateway
        let costs = [
            HatsCopy.quitCost(live.map(SessionsState.counted) ?? .unknown),
            HatsCopy.codexQuitCost(threads: threads),
        ].compactMap { $0 }
        guard !costs.isEmpty else {
            NSApp.terminate(nil)
            return
        }
        popover.close()
        afterThePopoverSettles {
            guard HatDialogs.hasConfirmedQuit(cost: costs.joined(separator: " ")) else { return }
            NSApp.terminate(nil)
        }
    }
}
