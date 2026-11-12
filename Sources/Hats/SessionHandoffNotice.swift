import Foundation

final class SessionHandoffNotice {
    static let text = "A new version of the session handoff plugin is ready. Open Settings to update."

    private let own: String
    private let notify: (_ title: String, _ body: String) -> Void
    private let findToldAbout: () -> String?
    private let setToldAbout: (String) -> Void

    init(
        own: String,
        notify: @escaping (_ title: String, _ body: String) -> Void,
        findToldAbout: @escaping () -> String?,
        setToldAbout: @escaping (String) -> Void
    ) {
        self.own = own
        self.notify = notify
        self.findToldAbout = findToldAbout
        self.setToldAbout = setToldAbout
    }

    func consider(_ face: SessionHandoffFace) {
        guard isWorthTelling(face) else { return }
        Journal.log("sessionHandoff.offered", [
            "version": own,
        ])
        notify("Session handoff plugin \(own)", Self.text)
        setToldAbout(own)
    }

    func isWorthTelling(_ face: SessionHandoffFace) -> Bool {
        guard face.findOffer(own: own) != nil, case .installed(_, _, true, _) = face else { return false }
        guard let told = findToldAbout().flatMap({ PluginVersion($0) }) else { return true }

        return PluginVersion(own).map { told < $0 } ?? false
    }
}
