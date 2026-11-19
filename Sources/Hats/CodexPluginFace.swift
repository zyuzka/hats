import Foundation

enum CodexPluginSource: Equatable {
    case absent
    case github
    case folder(String)
    case foreign(String)
}

enum CodexCopyState: Equatable {
    case same
    case differs(String)
    case unreadable(String)
}

enum CodexPluginFace: Equatable {
    case unread
    case noCodex
    case notInstalled
    case installed(version: String?, isEnabled: Bool)
    case fromFolder(version: String?, folder: String, copy: CodexCopyState)
    case notOurs(String)
    case unknown(String)

    var canInstall: Bool {
        switch self {
        case .notInstalled, .unknown: return true
        case .unread, .noCodex, .installed, .fromFolder, .notOurs: return false
        }
    }

    var canRemove: Bool {
        switch self {
        case .installed, .fromFolder: return true
        case .unread, .noCodex, .notInstalled, .notOurs, .unknown: return false
        }
    }

    var canRefresh: Bool {
        guard case .fromFolder(_, _, .differs) = self else { return false }
        return true
    }

    func findOffer(own: String) -> SessionHandoffOffer? {
        guard case .installed(let version?, _) = self,
              let installed = PluginVersion(version),
              let bundled = PluginVersion(own),
              installed < bundled else { return nil }

        return SessionHandoffOffer(installed: version, own: own)
    }
}

struct CodexPluginRecord: Equatable {
    let id: String
    let version: String?
    let isEnabled: Bool
    let path: String?
}

struct CodexMarketRecord: Equatable {
    let name: String
    let sourceType: String?
    let source: String?
}

struct CodexPluginReading: Equatable {
    let face: CodexPluginFace
    let source: CodexPluginSource?
}

enum CodexPluginProvenance {
    static let pluginName = "hats"
    static let marketplaceName = "hats"
    static let pluginID = "hats@hats"
    static let repository = "zyuzka/hats"
    static let bundledVersion = "0.1.0"

    static func getSource(_ markets: [CodexMarketRecord]) -> CodexPluginSource {
        guard let ours = markets.first(where: { $0.name == marketplaceName }) else { return .absent }
        let source = ours.source ?? ""
        if ours.sourceType == "git", isOurRepository(source) { return .github }
        if ours.sourceType == "local", source.hasPrefix("/") { return .folder(source) }
        let from = source.isEmpty ? "a source Codex does not name" : source

        return .foreign("the Codex marketplace named hats comes from \(from), not from \(repository)")
    }

    static func isOurRepository(_ source: String) -> Bool {
        var text = source.lowercased()
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix(".git") { text.removeLast(4) }
        let accepted = [
            repository,
            "https://github.com/" + repository,
            "http://github.com/" + repository,
            "git@github.com:" + repository,
            "ssh://git@github.com/" + repository,
        ]

        return accepted.contains(text)
    }

    static func isAnotherPluginNamedHats(_ record: CodexPluginRecord) -> Bool {
        let parts = record.id.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return false }

        return parts[0] == pluginName && parts[1] != marketplaceName
    }

    static func getFace(
        plugins: [CodexPluginRecord],
        source: CodexPluginSource,
        copy: (CodexPluginRecord, String) -> CodexCopyState
    ) -> CodexPluginFace {
        if let other = plugins.first(where: isAnotherPluginNamedHats) {
            return .notOurs("\(other.id) is installed in Codex: another plugin under the name hats")
        }
        if case .foreign(let reason) = source { return .notOurs(reason) }
        guard let ours = plugins.first(where: { $0.id == pluginID }) else { return .notInstalled }
        switch source {
        case .github:
            return .installed(version: ours.version, isEnabled: ours.isEnabled)
        case .folder(let root):
            guard let folder = ours.path else {
                let reason = "Codex lists no plugin folder for \(pluginID), so its copy cannot be compared"
                return .fromFolder(version: ours.version, folder: root, copy: .unreadable(reason))
            }
            return .fromFolder(version: ours.version, folder: folder, copy: copy(ours, folder))
        case .absent, .foreign:
            return .notOurs("\(pluginID) is installed in Codex, but no marketplace named hats is listed, so where "
                + "it came from cannot be told")
        }
    }
}
