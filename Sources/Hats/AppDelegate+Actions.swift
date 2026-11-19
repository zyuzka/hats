import AppKit

extension AppDelegate: HatsActions {
    func wear(_ id: String) {
        if ClaudeDoors.route(ofAClickOn: id, among: store.accounts) == .codex { return wearCodex(id) }
        changing = id
        let takenAway = whatTheWearTakesAway()
        redraw()
        afterThePopoverSettles { [weak self] in
            guard let self else { return }
            do {
                try self.store.activate(id,
                                        meters: self.wornMetersForTheJournal(),
                                        targetMeters: self.metersForTheJournal(of: id))
                self.settings.autoSwitchRecord = nil
                self.saveSettings()
                self.changing = nil
                self.syncWithWorld()
                self.usage.poll(self.hatsForUsage())
            } catch {
                self.putBackWhatTheWearTookAway(takenAway)
                self.changing = nil
                self.redrawAfterTheLiveSlotMayHaveMoved()
                HatDialogs.present(error)
            }
        }
    }

    func addHat(for tool: Tool) {
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self else { return }
            self.whenNoSignInIsRunning { [weak self] in
                guard let self, let wanted = HatDialogs.addHat(
                    remembered: self.store.accounts.compactMap(\.browser),
                    tool: tool
                ) else { return }
                if wanted.tool == .codex { return self.addCodexHat(wanted) }
                do {
                    var hat = try self.store.add(email: wanted.email, browser: wanted.browser)
                    if let name = wanted.name {
                        hat.name = name
                        try self.store.update(hat)
                    }
                    if let live = self.store.liveEmail(), Account.sameAddress(live, hat.email) {
                        try self.store.capture(into: hat.id)
                        self.syncWithWorld()
                        HatDialogs.inform("Already signed in", "\(hat.title) is the account in use right now, "
                            + "so its credentials were stored as they are. No login was needed.")
                        return
                    }
                    try self.login.begin(hat.id, expecting: hat.email)
                    self.redraw()
                } catch {
                    self.redrawAfterTheLiveSlotMayHaveMoved()
                    HatDialogs.present(error, title: "Could not add that hat")
                }
            }
        }
    }

    func relogin(_ id: String) {
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self, let hat = self.store.accounts.first(where: { $0.id == id }) else { return }
            self.whenNoSignInIsRunning { [weak self] in
                guard let self else { return }
                if hat.isSwitchable, !HatDialogs.hasConfirmedLoginAnyway(for: hat) { return }
                if hat.browser?.overridesBrowser != true {
                    self.chooseBrowserNow(id)
                    guard self.store.accounts.first(where: { $0.id == id })?.browser?.overridesBrowser == true
                    else { return }
                }
                if hat.wornTool == .codex { return self.reloginCodex(id) }
                do {
                    try self.login.begin(id, expecting: self.store.accounts.first { $0.id == id }?.email)
                } catch {
                    self.redraw()
                    HatDialogs.present(error, title: "Could not start that login")
                }
            }
        }
    }

    func rename(_ id: String) {
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self, var hat = self.store.accounts.first(where: { $0.id == id }),
                  let chosen = HatDialogs.rename(hat) else { return }
            hat.name = chosen
            self.apply(hat)
        }
    }

    func chooseBrowser(_ id: String) {
        popover.close()
        afterThePopoverSettles { [weak self] in self?.chooseBrowserNow(id) }
    }

    private func chooseBrowserNow(_ id: String) {
        guard var hat = store.accounts.first(where: { $0.id == id }),
              let chosen = HatDialogs.browser(for: hat, remembered: store.accounts.compactMap(\.browser)) else { return }
        hat.browser = chosen
        apply(hat)
    }

    private func apply(_ hat: Account) {
        do {
            try store.update(hat)
            redraw()
        } catch {
            redraw()
            HatDialogs.present(error, title: "Could not save that change")
        }
    }

    func setVacation(_ id: String, on: Bool) {
        VacationChange(
            redraw: { [weak self] in self?.redraw() },
            poll: { [weak self] in
                guard let self else { return }
                self.usage.poll(self.hatsForUsage())
            },
            sayItCouldNotSave: { HatDialogs.present($0, title: "Could not save that change") }
        ).apply(id, on: on, at: Date(), in: store)
    }

    func remove(_ id: String) {
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self, let hat = self.store.accounts.first(where: { $0.id == id }),
                  HatDialogs.hasConfirmedRemoval(of: hat),
                  self.hasConfirmedLosingTheCodexGateway(by: hat) else { return }
            do {
                try self.store.remove(id)
                self.settings.forgetInTheSwitches(id)
                self.saveSettings()
                self.redraw()
                self.usage.poll(self.hatsForUsage())
            } catch {
                self.redraw()
                HatDialogs.present(error, title: "Could not remove that hat")
            }
        }
    }
}
