import AppKit

extension AppDelegate {
    func checkForUpdates() {
        popover.close()
        askGitHub { [weak self] verdict in self?.announce(verdict) }
    }

    func watchForUpdates() {
        Notifier.askOnce()
        updates.start { [weak self] in
            self?.askGitHub { [weak self] verdict in self?.noteQuietly(verdict) }
        }
    }

    private func askGitHub(then answer: @escaping (UpdateVerdict) -> Void) {
        guard let repository = UpdateCheck.repository() else { return answer(.notConfigured) }
        let running = popover.model.snapshot.version
        DispatchQueue.global(qos: .userInitiated).async {
            let verdict = OneShotRequest.answer(
                to: UpdateCheck.request(endpoint: UpdateCheck.endpoint(for: repository)),
                within: UpdateCheck.budget,
                unreachable: UpdateVerdict.unreachable,
                reading: { status, body in
                    UpdateCheck.verdict(status: status, body: body, running: running)
                }
            )
            DispatchQueue.main.async { answer(verdict) }
        }
    }

    private func noteQuietly(_ verdict: UpdateVerdict) {
        guard case .available(let release) = verdict else { return }
        updateWaiting = release.version
        redraw()
        guard UpdateAnnouncement.isWorthAnnouncing(
            release.version, announced: settings.announcedUpdate
        ) else { return }
        settings.announcedUpdate = release.version
        saveSettings()
        let notice = HatsCopy.updateAnnouncement(release.version)
        Notifier.post(title: notice.title, body: notice.body)
        Journal.log("update.announced", ["version": release.version])
    }

    private func announce(_ verdict: UpdateVerdict) {
        let copy = HatsCopy.updateVerdict(verdict)
        let alert = NSAlert()
        alert.messageText = copy.message
        alert.informativeText = copy.detail
        guard case .available(let release) = verdict else {
            alert.addButton(withTitle: "OK")
            _ = HatDialogs.run(alert)
            return
        }
        alert.addButton(withTitle: release.asset == nil ? "Open the release page" : "Download")
        alert.addButton(withTitle: "Later")
        guard HatDialogs.run(alert) == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(release.asset ?? release.page)
        Journal.log("update.offered", ["version": release.version])
    }
}
