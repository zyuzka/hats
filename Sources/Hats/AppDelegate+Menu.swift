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

    func showReleases() {
        popover.close()
        afterThePopoverSettles { [weak self] in
            guard let self else { return }
            self.releases.show(running: self.popover.model.snapshot.version)
        }
    }

    func quit() {
        let live = SessionDiscovery.everySessionSeenRecently()
        guard let cost = HatsCopy.quitCost(live.map(SessionsState.counted) ?? .unknown) else {
            NSApp.terminate(nil)
            return
        }
        popover.close()
        afterThePopoverSettles {
            guard HatDialogs.hasConfirmedQuit(cost: cost) else { return }
            NSApp.terminate(nil)
        }
    }
}
