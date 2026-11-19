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
        let notice = CodexPluginNotice.remembering(
            own: codexPlugin.own,
            notify: { Notifier.postOpeningSettings(title: $0, body: $1) },
            settings: { [weak self] in self?.settings },
            keep: { [weak self] in self?.settings = $0 },
            save: { [weak self] in self?.saveSettings() }
        )
        codexPlugin.refresh { notice.consider($0) }
    }
}
