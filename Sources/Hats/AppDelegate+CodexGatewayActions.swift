import AppKit

extension AppDelegate {
    var codexGatewayFace: CodexGatewayFace {
        CodexGatewayFace(
            status: codex.gateway.status,
            hasCodexHats: !store.codexHats.isEmpty,
            configNote: codex.gateway.configNote,
            threads: codex.gateway.isServing ? codex.gateway.state.threadIDs.count : 0
        )
    }

    func setCodexGateway(enabled: Bool) {
        askBeforeTheCodexThreadsLoseTheGateway(skipping: enabled) { [weak self] in
            guard let self else { return }
            self.settings.isCodexGatewayEnabled = enabled
            self.saveSettings()
            self.syncTheCodexGateway()
            self.redraw()
        }
    }

    func applyCodexGatewayPort(_ port: Int) {
        guard AppSettings.isAUsablePort(port), port != settings.codexGatewayPort else { return }
        askBeforeTheCodexThreadsLoseTheGateway(skipping: false) { [weak self] in
            guard let self else { return }
            self.settings.codexGatewayPort = port
            self.saveSettings()
            self.syncTheCodexGateway()
            self.redraw()
        }
    }

    func hasConfirmedLosingTheCodexGateway(by hat: Account) -> Bool {
        let decision = GatewayStopDecision.ofRemoving(
            hat,
            codexHats: store.codexHats,
            isServing: codex.gateway.isServing,
            threads: codex.gateway.state.threadIDs.count
        )
        guard case .ask(let cost) = decision else { return true }
        guard HatDialogs.hasConfirmedStoppingTheGateway(cost: cost) else {
            Journal.log("codexGateway.removalDeclined", ["hat": String(hat.id.prefix(8))])
            return false
        }
        return true
    }

    private func askBeforeTheCodexThreadsLoseTheGateway(skipping: Bool, then: @escaping () -> Void) {
        let threads = codex.gateway.isServing ? codex.gateway.state.threadIDs.count : 0
        guard !skipping, let cost = HatsCopy.codexGatewayStopCost(threads: threads) else { return then() }
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard HatDialogs.hasConfirmedStoppingTheGateway(cost: cost) else {
                Journal.log("codexGateway.stopDeclined", ["threads": String(threads)])
                self?.redraw()
                return
            }
            then()
        }
    }
}
