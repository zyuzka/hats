import Foundation

final class CodexPluginNotice {
    static let text = "A new version of the Codex plugin is ready. Open Settings to update."

    private let own: String
    private let notify: (_ title: String, _ body: String) -> Void
    private let findToldAbout: () -> String?
    private let setToldAbout: (String) -> Void
    private let journal: (_ operation: String, _ details: [String: String]) -> Void

    init(
        own: String,
        notify: @escaping (_ title: String, _ body: String) -> Void,
        findToldAbout: @escaping () -> String?,
        setToldAbout: @escaping (String) -> Void,
        journal: @escaping (_ operation: String, _ details: [String: String]) -> Void = Journal.log
    ) {
        self.own = own
        self.notify = notify
        self.findToldAbout = findToldAbout
        self.setToldAbout = setToldAbout
        self.journal = journal
    }

    func consider(_ face: CodexPluginFace) {
        guard isWorthTelling(face) else { return }
        journal("codexPlugin.offered", [
            "version": own,
        ])
        notify("Codex plugin \(own)", Self.text)
        setToldAbout(own)
    }

    func isWorthTelling(_ face: CodexPluginFace) -> Bool {
        guard face.findOffer(own: own) != nil, case .installed(_, true) = face else { return false }
        guard let told = findToldAbout().flatMap({ PluginVersion($0) }) else { return true }

        return PluginVersion(own).map { told < $0 } ?? false
    }
}

extension CodexPluginNotice {
    static func remembering(
        own: String,
        notify: @escaping (_ title: String, _ body: String) -> Void,
        settings: @escaping () -> AppSettings?,
        keep: @escaping (AppSettings) -> Void,
        savingTo url: URL = AppSettings.defaultURL
    ) -> CodexPluginNotice {
        CodexPluginNotice(
            own: own,
            notify: notify,
            findToldAbout: { settings()?.codexPluginVersionToldAbout },
            setToldAbout: { version in
                guard var changed = settings() else { return }
                changed.codexPluginVersionToldAbout = version
                keep(changed)
                do {
                    try changed.save(to: url)
                } catch {
                    Journal.log("settings.notSaved", ["reason": error.localizedDescription])
                }
            }
        )
    }
}

extension HatsSnapshot {
    mutating func showTheCodexPluginRow(of flow: CodexPluginFlow) {
        codexPlugin = flow.row
    }
}
