import Foundation

extension CodexPluginSteps {
    static func getChange(_ plan: CodexPluginPlan, own: String, in world: PluginWorld) -> CodexPluginReport {
        let before = findReading(of: plan.target, in: world)
        if case .unknown(let reason) = before.face {
            return CodexPluginReport(
                title: CodexPluginText.getFailureTitle(plan.action),
                text: "Nothing was changed. " + reason,
                face: before.face,
                isChanged: false
            )
        }
        let isUnchanged = getCommands(plan.action, reading: before, own: own) == plan.commands
            && before.face.findOffer(own: own)?.installed == plan.installed
        guard isUnchanged else {
            return CodexPluginReport(
                title: CodexPluginText.getFailureTitle(plan.action),
                text: CodexPluginText.getChangedMeanwhile(before.face),
                face: before.face,
                isChanged: false
            )
        }
        var answer = PluginChangeAnswer(isDone: true, message: "ok")
        var command = ""
        for arguments in plan.commands {
            let outcome = world.run(plan.target.createLine(arguments, seconds: changeSeconds))
            answer = CodexPluginListing.getAnswer(of: outcome, findTrouble: findTrouble(for: arguments))
            command = "codex " + arguments.filter { $0 != "--json" }.joined(separator: " ")
            guard answer.isDone else { break }
        }
        let after = findReading(of: plan.target, in: world).face

        return CodexPluginText.getReport(
            plan.action,
            isReached: isReached(plan, after: after),
            answer: answer,
            command: command,
            after: after
        )
    }

    static func findTrouble(for arguments: [String]) -> ([String: Any]) -> String? {
        switch arguments {
        case marketAddArguments: return CodexPluginListing.findMarketTrouble
        case upgradeArguments: return CodexPluginListing.findUpgradeTrouble
        default: return CodexPluginListing.findPluginTrouble
        }
    }

    static func isReached(_ plan: CodexPluginPlan, after: CodexPluginFace) -> Bool {
        switch plan.action {
        case .install:
            return after.canRemove
        case .update:
            guard case .installed(let version?, _) = after,
                  let listed = PluginVersion(version),
                  let before = PluginVersion(plan.installed ?? "") else { return false }
            return listed > before
        case .refresh:
            guard case .fromFolder(_, _, .same) = after else { return false }
            return true
        case .remove:
            return after == .notInstalled
        }
    }
}
