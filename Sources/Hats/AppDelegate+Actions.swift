import AppKit

extension AppDelegate: HatsActions {
    func wear(_ id: String) {
        changing = id
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
                self.changing = nil
                self.redrawAfterTheLiveSlotMayHaveMoved()
                HatDialogs.present(error)
            }
        }
    }

    func addHat() {
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self, let wanted = HatDialogs.addHat() else { return }
            guard self.login.canStartALogin() else {
                HatDialogs.refuseASecondLogin()
                return
            }
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

    func relogin(_ id: String) {
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self, let hat = self.store.accounts.first(where: { $0.id == id }) else { return }
            guard self.login.canStartALogin() else {
                HatDialogs.refuseASecondLogin()
                return
            }
            if hat.isSwitchable, !HatDialogs.hasConfirmedLoginAnyway(for: hat) { return }
            if hat.browser?.overridesBrowser != true {
                self.chooseBrowserNow(id)
                guard self.store.accounts.first(where: { $0.id == id })?.browser?.overridesBrowser == true
                else { return }
            }
            do {
                try self.login.begin(id, expecting: self.store.accounts.first { $0.id == id }?.email)
            } catch {
                self.redraw()
                HatDialogs.present(error, title: "Could not start that login")
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
              let chosen = HatDialogs.browser(for: hat) else { return }
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

    func remove(_ id: String) {
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self, let hat = self.store.accounts.first(where: { $0.id == id }),
                  HatDialogs.hasConfirmedRemoval(of: hat) else { return }
            do {
                try self.store.remove(id)
                self.settings.autoSwitch.order.removeAll { $0 == id }
                self.saveSettings()
                self.redraw()
            } catch {
                self.redraw()
                HatDialogs.present(error, title: "Could not remove that hat")
            }
        }
    }

    func wornMetersForTheJournal() -> MeterReading {
        guard let id = hatsForUsage().first(where: \.isWearing)?.id else { return .unavailable }
        return metersForTheJournal(of: id)
    }

    func metersForTheJournal(of id: String) -> MeterReading {
        MeterReading.of(usage.readings[id], readAt: usage.readAt[id], trouble: usage.troubles[id])
    }

    func afterThePopoverSettles(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
