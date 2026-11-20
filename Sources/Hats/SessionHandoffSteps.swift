import Foundation

enum SessionHandoffSteps {
    static let installSeconds: TimeInterval = 120
    static let helpArguments = [
        "plugin",
        "install",
        "--help",
    ]
    static let listArguments = [
        "plugin",
        "list",
        "--json",
    ]
    static let marketplaceArguments = [
        "plugin",
        "marketplace",
        "list",
        "--json",
    ]
    static let removeArguments = [
        "plugin",
        "uninstall",
        SessionHandoffProvenance.pluginID,
        "--scope",
        SessionHandoffProvenance.userScope,
        "--keep-data",
        "--json",
    ]

    static func findFace(in world: PluginWorld) -> SessionHandoffFace {
        switch SessionHandoffTargets.find(in: world) {
        case .failure(let refusal): return .unknown(SessionHandoffCopy.getText(refusal))
        case .success(let target): return findReading(of: target, in: world).face
        }
    }

    static func findReading(of target: SessionHandoffTarget, in world: PluginWorld) -> SessionHandoffReading {
        let seconds = SessionHandoffTargets.commandSeconds
        let listed = world.run(target.createLine(listArguments, seconds: seconds))
        let plugins = SessionHandoffListing.findPlugins(in: listed)
        guard case .success(let records) = plugins else {
            return SessionHandoffReading(face: .unknown(SessionHandoffCopy.getListTrouble(plugins)), source: nil)
        }
        let marketplaces = SessionHandoffListing.findMarketplaces(
            in: world.run(target.createLine(marketplaceArguments, seconds: seconds))
        )
        guard case .success(let markets) = marketplaces else {
            return SessionHandoffReading(face: .unknown(SessionHandoffCopy.getSourceTrouble(marketplaces)), source: nil)
        }
        let source = SessionHandoffProvenance.getSource(markets)

        return SessionHandoffReading(
            face: SessionHandoffProvenance.getFace(plugins: records, source: source),
            source: source
        )
    }

    static func getPreparation(in world: PluginWorld) -> SessionHandoffPreparation {
        let target: SessionHandoffTarget
        switch SessionHandoffTargets.find(in: world) {
        case .failure(let refusal): return .refused(refusal)
        case .success(let found): target = found
        }
        let python: SessionHandoffPythonFound
        switch SessionHandoffPython.find(for: target, in: world) {
        case .failure(let refusal): return .refused(refusal)
        case .success(let found): python = found
        }
        if let refusal = SessionHandoffOldHook.findRefusal(configFolder: target.configFolder, in: world) {
            return .refused(refusal)
        }
        if let refusal = findHelpRefusal(target, in: world) { return .refused(refusal) }
        let reading = findReading(of: target, in: world)
        guard case .notInstalled = reading.face, let source = reading.source else { return .settled(reading.face) }
        let folder: String?
        if case .folder(let path) = source { folder = path } else { folder = nil }
        let plan = SessionHandoffPlan(
            target: target,
            source: SessionHandoffProvenance.getInstallSource(source),
            folder: folder,
            python: python
        )

        return .ready(plan, reading.face)
    }

    static func findHelpRefusal(_ target: SessionHandoffTarget, in world: PluginWorld) -> SessionHandoffRefusal? {
        let outcome = world.run(target.createLine(helpArguments, seconds: SessionHandoffTargets.commandSeconds))
        if let trouble = outcome.trouble {
            return .cliDidNotAnswer(command: "claude plugin install --help", reason: trouble)
        }
        let text = (outcome.stdoutText ?? "") + (String(bytes: outcome.stderr, encoding: .utf8) ?? "")

        return text.contains("--marketplace") ? nil : .cliTooOld(
            path: target.cli,
            command: "claude plugin install",
            option: "--marketplace"
        )
    }

    static func getInstallChange(_ plan: SessionHandoffPlan, in world: PluginWorld) -> SessionHandoffChange {
        if let refusal = SessionHandoffOldHook.findRefusal(configFolder: plan.target.configFolder, in: world) {
            return SessionHandoffChange(refusal: refusal)
        }
        let before = findReading(of: plan.target, in: world)
        let source = before.source.map(SessionHandoffProvenance.getInstallSource)
        guard case .notInstalled = before.face, source == plan.source else {
            let failure = SessionHandoffCopy.getChangedMeanwhile(before.face)
            return SessionHandoffChange(failure: failure, face: before.face)
        }
        let outcome = world.run(plan.target.createLine(plan.arguments, seconds: installSeconds))
        let after = findReading(of: plan.target, in: world).face

        return SessionHandoffChange.createJudged(
            SessionHandoffListing.getAnswer(of: outcome),
            command: "claude plugin install",
            after: after,
            isReached: after.canRemove
        )
    }

    static func getRemoveChange(folder: String, in world: PluginWorld) -> SessionHandoffChange {
        let target: SessionHandoffTarget
        switch SessionHandoffTargets.find(in: world) {
        case .failure(let refusal): return SessionHandoffChange(refusal: refusal)
        case .success(let found): target = found
        }
        guard target.configFolder == folder else {
            return SessionHandoffChange(failure: "The settings folder changed from \(folder) to "
                + "\(target.configFolder) after you agreed, so nothing was removed. Open the settings again.")
        }
        let before = findReading(of: target, in: world).face
        guard before.canRemove else {
            let failure = "Nothing to remove. " + SessionHandoffCopy.getStatus(before)
            return SessionHandoffChange(failure: failure, face: before)
        }
        let seconds = SessionHandoffTargets.commandSeconds
        let removed = world.run(target.createLine(removeArguments, seconds: seconds))
        let after = findReading(of: target, in: world).face
        var isReached = false
        if case .notInstalled = after { isReached = true }

        return SessionHandoffChange.createJudged(
            SessionHandoffListing.getAnswer(of: removed),
            command: "claude plugin uninstall",
            after: after,
            isReached: isReached
        )
    }
}
