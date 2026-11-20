import AppKit

extension AppDelegate {
    var isTheCodexGatewayWanted: Bool {
        CodexGatewayWanted.isWanted(hasCodexHats: !store.codexHats.isEmpty, enabled: settings.isCodexGatewayEnabled)
    }

    func listenToTheCodexGateway() {
        let broker = codex.gateway.broker
        broker.onWorn = { [weak self] id, worn, renewed in
            guard let self else { return }
            do {
                try self.store.noteCodexWear(id, outcome: worn, renewed: renewed)
            } catch {
                Journal.log("codexGateway.wearNotRecorded", ["reason": error.localizedDescription])
            }
            self.dropTheCodexSwitchBack()
            self.redraw()
        }
        broker.onLogin = { [weak self] id, data in
            self?.store.noteCodexLogin(id, login: data, signedIn: false)
            self?.redraw()
        }
        broker.onNeedsSignIn = { [weak self] id, why in
            self?.store.noteCodexRenewals([.needsSignIn(id, why)])
            self?.redraw()
        }
        broker.onAllAtLimit = { Notifier.post(title: HatsCopy.codexAllAtLimitTitle, body: HatsCopy.codexAllAtLimit) }
        codex.gateway.state.onReading = { [weak self] id, sighting in
            DispatchQueue.main.async {
                guard let self, self.codex.usage.note(sighting, for: id) == .taken else { return }
                self.redraw()
                self.decideCodexAutoSwitch(from: .aPollLanded)
            }
        }
    }

    func syncTheCodexGatewayIfItsInputsMoved() {
        let inputs = CodexGatewayInputs(
            hats: codexGatewayHats,
            wanted: isTheCodexGatewayWanted,
            port: settings.codexGatewayPort,
            secret: settings.codexGatewaySecret
        )
        guard codex.gateway.lastInputs != inputs else { return }
        syncTheCodexGateway()
    }

    private var codexGatewayHats: CodexGatewayHats {
        CodexGatewayHats(
            all: store.codexTickets,
            candidates: store.codexHats.filter { $0.vacationSince == nil }.compactMap { store.codexTicket($0) }
        )
    }

    func syncTheCodexGateway() {
        let run = codex.gateway
        run.broker.hats = codexGatewayHats
        let wanted = isTheCodexGatewayWanted
        if settings.hasCodexHats != !store.codexHats.isEmpty || (wanted && settings.codexGatewaySecret == nil)
            || (wanted && settings.isCodexGatewayEnabled == nil) {
            settings.hasCodexHats = !store.codexHats.isEmpty
            if wanted { settings.codexGatewaySecret = settings.codexGatewaySecret ?? CodexGatewayPaths.newSecret() }
            if wanted { settings.isCodexGatewayEnabled = settings.isCodexGatewayEnabled ?? true }
            saveSettings()
        }
        let secret = settings.codexGatewaySecret
        let port = settings.codexGatewayPort
        let created = settings.codexConfigCreatedByHats
        run.lastInputs = CodexGatewayInputs(hats: run.broker.hats, wanted: wanted, port: port, secret: secret)
        run.queue.async { [weak self] in
            var flag = created
            var served: GatewayProcess.Status?
            if wanted, let secret {
                served = run.serve(port: port, secret: secret, recheck: true, createdByHats: &flag)
            } else if run.isServing {
                run.retire(secret: secret, createdByHats: &flag)
            } else {
                run.hasRemovedConfig(secret: secret, createdByHats: &flag)
            }
            DispatchQueue.main.async { self?.settleTheCodexGateway(served: served, createdByHats: flag) }
        }
    }

    private func settleTheCodexGateway(served: GatewayProcess.Status?, createdByHats: Bool) {
        if createdByHats != settings.codexConfigCreatedByHats {
            settings.codexConfigCreatedByHats = createdByHats
            saveSettings()
        }
        if served?.isServing == true, CodexGatewayRun.isTheFirstStart(told: &settings.hasToldToRestartCodexWindows) {
            saveSettings()
            Notifier.post(title: HatsCopy.codexRestartWindowsTitle, body: HatsCopy.codexRestartWindows)
            Journal.log("codexGateway.toldToRestartWindows")
        }
        redraw()
    }

    func stopEveryGateway() {
        let run = codex.gateway
        var flag = settings.codexConfigCreatedByHats
        let secret = settings.codexGatewaySecret
        run.queue.sync { run.retire(secret: secret, createdByHats: &flag) }
        if flag != settings.codexConfigCreatedByHats {
            settings.codexConfigCreatedByHats = flag
            saveSettings()
        }
        GatewayProcess.stop()
        gatewayEnvironment = GatewayEnvironment.ensure(serving: false)
    }

    func renewTheWornCodexHat() {
        guard codex.gateway.isServing, let id = store.codexActiveID,
              let hat = store.codexHats.first(where: { $0.id == id }),
              let ticket = store.codexTicket(hat) else { return }
        codex.gateway.broker.renewTheWorn(ticket)
    }
}
