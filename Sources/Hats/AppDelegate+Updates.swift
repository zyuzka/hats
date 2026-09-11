import AppKit

extension AppDelegate {
    func checkForUpdates() {
        popover.close()
        guard let repository = UpdateCheck.repository() else {
            announce(.notConfigured)
            return
        }
        let running = popover.model.snapshot.version
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let verdict = OneShotRequest.answer(
                to: UpdateCheck.request(endpoint: UpdateCheck.endpoint(for: repository)),
                within: UpdateCheck.budget,
                unreachable: UpdateVerdict.unreachable,
                reading: { status, body in
                    UpdateCheck.verdict(status: status, body: body, running: running)
                }
            )
            DispatchQueue.main.async { self?.announce(verdict) }
        }
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
