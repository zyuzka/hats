import AppKit

extension AppDelegate {
    func installSessionHandoff() {
        handoff.install()
    }

    func updateSessionHandoff() {
        handoff.update()
    }

    func offerThePluginUpdateOnce() {
        let notice = SessionHandoffNotice(
            own: handoff.own,
            notify: { Notifier.postOpeningSettings(title: $0, body: $1) },
            findToldAbout: { [weak self] in self?.settings.pluginVersionToldAbout },
            setToldAbout: { [weak self] version in
                self?.settings.pluginVersionToldAbout = version
                self?.saveSettings()
            }
        )
        handoff.refresh { notice.consider($0) }
    }

    func removeSessionHandoff() {
        handoff.remove()
    }
}
