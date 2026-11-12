import Foundation

enum SessionHandoffSource: Equatable {
    case absent
    case github
    case folder(String)
    case foreign(String)
}

enum SessionHandoffFace: Equatable {
    case unread
    case notInstalled(elsewhere: [PluginRecord])
    case installed(version: String?, folder: String?, isEnabled: Bool, elsewhere: [PluginRecord])
    case notOurs(String)
    case unknown(String)

    var canInstall: Bool {
        switch self {
        case .notInstalled, .unknown: return true
        case .unread, .installed, .notOurs: return false
        }
    }

    var canRemove: Bool {
        guard case .installed = self else { return false }
        return true
    }
}

enum SessionHandoffProvenance {
    static let pluginName = "hats"
    static let marketplaceName = "hats"
    static let pluginID = "hats@hats"
    static let repository = "zyuzka/hats"
    static let userScope = "user"

    static func getSource(_ marketplaces: [MarketplaceRecord]) -> SessionHandoffSource {
        guard let ours = marketplaces.first(where: { $0.name == marketplaceName }) else { return .absent }
        if ours.source == "github", ours.repo?.lowercased() == repository { return .github }
        if ours.source == "directory", let path = ours.path { return .folder(path) }
        let from = ours.repo ?? ours.path ?? "a \(ours.source) source"

        return .foreign("the marketplace named hats comes from \(from), not from \(repository)")
    }

    static func getFace(plugins: [PluginRecord], source: SessionHandoffSource) -> SessionHandoffFace {
        if let other = plugins.first(where: isAnotherPluginNamedHats) {
            return .notOurs("\(other.id) is installed: another plugin under the name hats")
        }
        if case .foreign(let reason) = source { return .notOurs(reason) }
        let ours = plugins.filter { $0.id == pluginID }
        let elsewhere = ours.filter { $0.scope != userScope }
        guard let user = ours.first(where: { $0.scope == userScope }) else {
            return .notInstalled(elsewhere: elsewhere)
        }
        switch source {
        case .github:
            return .installed(
                version: user.version,
                folder: nil,
                isEnabled: user.isEnabled,
                elsewhere: elsewhere
            )
        case .folder(let path):
            return .installed(
                version: user.version,
                folder: path,
                isEnabled: user.isEnabled,
                elsewhere: elsewhere
            )
        case .absent, .foreign:
            return .notOurs("\(pluginID) is installed, but no marketplace named hats is listed, so where it came "
                + "from cannot be told")
        }
    }

    static func isAnotherPluginNamedHats(_ record: PluginRecord) -> Bool {
        let parts = record.id.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return false }

        return parts[0] == pluginName && parts[1] != marketplaceName
    }

    static func getInstallSource(_ source: SessionHandoffSource) -> String {
        guard case .folder(let path) = source else { return repository }
        return path
    }
}
