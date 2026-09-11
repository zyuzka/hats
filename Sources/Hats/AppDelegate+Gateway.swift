import AppKit

extension AppDelegate {
    static var portList: String {
        GatewayProcess.heldPorts.map(String.init).joined(separator: ",")
    }

    func setGateway(enabled: Bool) {
        let decision = GatewayStopDecision.of(
            enabled: enabled,
            ports: GatewayProcess.heldPorts,
            sessions: SessionDiscovery.everySessionSeenRecently()
        )
        guard case .ask(let cost) = decision else {
            applyGateway(enabled: enabled)
            return
        }
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self else { return }
            guard HatDialogs.hasConfirmedStoppingTheGateway(cost: cost) else {
                Journal.log("gateway.stopDeclined", ["ports": Self.portList])
                self.redraw()
                return
            }
            self.applyGateway(enabled: false)
        }
    }

    private func applyGateway(enabled: Bool) {
        settings.isGatewayEnabled = enabled
        saveSettings()
        startOrStopTheGateway()
        redraw()
    }

    func applyGatewayPort(_ port: Int) {
        guard AppSettings.isAUsablePort(port) else { return }
        guard settings.isGatewayEnabled else {
            settings.gatewayPort = port
            GatewayProcess.port = port
            saveSettings()
            gatewayEnvironment = GatewayEnvironment.ensure(serving: false)
            redraw()
            return
        }
        let status = GatewayProcess.moveTo(port: port, settle: settleWanted)
        if status.isServing, GatewayProcess.port == port {
            settings.gatewayPort = port
            saveSettings()
            gatewayEnvironment = GatewayEnvironment.ensure(serving: true)
        }
        redraw()
    }

    func applyGatewaySettle(_ seconds: Int) {
        guard AppSettings.isAUsableSettle(seconds), seconds != settings.gatewaySettleSeconds else { return }
        settings.gatewaySettleSeconds = seconds
        saveSettings()
        GatewayProcess.applySettle(TimeInterval(seconds))
        redraw()
    }

    func restartGateway() {
        let decision = GatewayStopDecision.forARestart(
            ports: GatewayProcess.heldPorts,
            sessions: SessionDiscovery.everySessionSeenRecently()
        )
        guard case .ask(let cost) = decision else {
            startOrStopTheGateway()
            redraw()
            return
        }
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self else { return }
            guard HatDialogs.hasConfirmedRestartingTheGateway(cost: cost) else {
                Journal.log("gateway.restartDeclined", ["ports": Self.portList])
                self.redraw()
                return
            }
            self.startOrStopTheGateway()
            self.redraw()
        }
    }

    func takeOverProfile() {
        gatewayEnvironment = GatewayEnvironment.takeOver(serving: GatewayProcess.status.isServing)
        settings.foreignProfileResolution = .undecided
        saveSettings()
        redraw()
    }

    func keepMyProfile() {
        settings.foreignProfileResolution = .keepMine
        saveSettings()
        Journal.log("gateway.profileKeptByTheUser")
        redraw()
    }

    func copyVariables() {
        let dialect = ShellProfile.currentTarget()?.dialect ?? .posix
        let block = ShellEnvironment.block(baseURL: GatewayProcess.baseURL, dialect: dialect)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block, forType: .string)
    }

    func openLog() {
        NSWorkspace.shared.open(Journal.url)
    }
}
