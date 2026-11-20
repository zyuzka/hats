import Foundation

enum CodexPluginAction: String, Equatable {
    case install
    case update
    case refresh
    case remove
}

struct CodexPluginPlan: Equatable {
    let action: CodexPluginAction
    let target: CodexPluginTarget
    let commands: [[String]]
    let installed: String?
}

enum CodexPluginPreparation: Equatable {
    case ready(CodexPluginPlan, CodexPluginFace)
    case refused(String, CodexPluginFace)
    case settled(CodexPluginFace)
}

enum CodexPluginSteps {
    static let readSeconds: TimeInterval = 30
    static let changeSeconds: TimeInterval = 120
    static let listArguments = [
        "plugin",
        "list",
        "--json",
    ]
    static let marketListArguments = [
        "plugin",
        "marketplace",
        "list",
        "--json",
    ]
    static let marketAddArguments = [
        "plugin",
        "marketplace",
        "add",
        CodexPluginProvenance.repository,
        "--json",
    ]
    static let upgradeArguments = [
        "plugin",
        "marketplace",
        "upgrade",
        CodexPluginProvenance.marketplaceName,
        "--json",
    ]
    static let addArguments = [
        "plugin",
        "add",
        CodexPluginProvenance.pluginID,
        "--json",
    ]
    static let removeArguments = [
        "plugin",
        "remove",
        CodexPluginProvenance.pluginID,
        "--json",
    ]

    static func findFace(in world: PluginWorld) -> CodexPluginFace {
        guard let target = CodexPluginTargets.find(in: world) else { return .noCodex }
        return findReading(of: target, in: world).face
    }

    static func findReading(of target: CodexPluginTarget, in world: PluginWorld) -> CodexPluginReading {
        let listed = world.run(target.createLine(listArguments, seconds: readSeconds))
        let plugins = CodexPluginListing.findPlugins(in: listed)
        guard case .success(let records) = plugins else {
            return CodexPluginReading(face: .unknown(CodexPluginText.getListTrouble(plugins)), source: nil)
        }
        let markets = CodexPluginListing.findMarkets(
            in: world.run(target.createLine(marketListArguments, seconds: readSeconds))
        )
        guard case .success(let found) = markets else {
            return CodexPluginReading(face: .unknown(CodexPluginText.getMarketTrouble(markets)), source: nil)
        }
        let source = CodexPluginProvenance.getSource(found)
        let face = CodexPluginProvenance.getFace(plugins: records, source: source) { record, folder in
            guard let version = record.version, PluginVersion(version) != nil else {
                return .unreadable("Codex lists no usable version of the plugin, so its copy cannot be found")
            }
            let copy = CodexPluginCopy.getCachePath(codexHome: target.codexHome, version: version)
            return world.compareCopy(copy, folder)
        }

        return CodexPluginReading(face: face, source: source)
    }

    static func getCommands(
        _ action: CodexPluginAction,
        reading: CodexPluginReading,
        own: String
    ) -> [[String]]? {
        switch action {
        case .install:
            guard case .notInstalled = reading.face, let source = reading.source else { return nil }
            return source == .absent ? [marketAddArguments, addArguments] : [addArguments]
        case .update:
            return reading.face.findOffer(own: own) == nil ? nil : [upgradeArguments, addArguments]
        case .refresh:
            return reading.face.canRefresh ? [addArguments] : nil
        case .remove:
            return reading.face.canRemove ? [removeArguments] : nil
        }
    }

    static func getPreparation(
        _ action: CodexPluginAction,
        own: String,
        in world: PluginWorld
    ) -> CodexPluginPreparation {
        guard let target = CodexPluginTargets.find(in: world) else {
            return .refused(CodexPluginText.getStatus(.noCodex), .noCodex)
        }
        let reading = findReading(of: target, in: world)
        if case .unknown(let reason) = reading.face { return .refused(reason, reading.face) }
        guard let commands = getCommands(action, reading: reading, own: own) else { return .settled(reading.face) }
        let plan = CodexPluginPlan(
            action: action,
            target: target,
            commands: commands,
            installed: reading.face.findOffer(own: own)?.installed
        )

        return .ready(plan, reading.face)
    }
}
