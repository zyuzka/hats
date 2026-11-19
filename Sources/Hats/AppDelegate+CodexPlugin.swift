import AppKit

extension AppDelegate {
    func installCodexPlugin() {
        codexPlugin.install()
    }

    func updateCodexPlugin() {
        codexPlugin.update()
    }

    func refreshCodexPlugin() {
        codexPlugin.refreshCopy()
    }

    func removeCodexPlugin() {
        codexPlugin.remove()
    }

    func offerTheCodexPluginUpdateOnce() {
        let notice = CodexPluginNotice(
            own: codexPlugin.own,
            notify: { Notifier.postOpeningSettings(title: $0, body: $1) },
            findToldAbout: { [weak self] in self?.settings.codexPluginVersionToldAbout },
            setToldAbout: { [weak self] version in
                self?.settings.codexPluginVersionToldAbout = version
                self?.saveSettings()
            }
        )
        codexPlugin.refresh { notice.consider($0) }
    }
}
