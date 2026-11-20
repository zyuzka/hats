import Foundation

struct SessionHandoffUpdatePlan: Equatable {
    let target: SessionHandoffTarget
    let installed: String
    let own: String
}

enum SessionHandoffUpdatePreparation: Equatable {
    case ready(SessionHandoffUpdatePlan, SessionHandoffFace)
    case refused(SessionHandoffRefusal)
    case settled(SessionHandoffFace)
}

struct SessionHandoffHelp: Equatable {
    let command: String
    let arguments: [String]
}

enum SessionHandoffUpdateSteps {
    static let refreshCommand = "claude plugin marketplace update"
    static let updateCommand = "claude plugin update"
    static let refreshArguments = [
        "plugin",
        "marketplace",
        "update",
        SessionHandoffProvenance.marketplaceName,
        "--json",
    ]
    static let updateArguments = [
        "plugin",
        "update",
        SessionHandoffProvenance.pluginID,
        "--scope",
        SessionHandoffProvenance.userScope,
        "--json",
    ]
    static let helps = [
        SessionHandoffHelp(
            command: refreshCommand,
            arguments: [
                "plugin",
                "marketplace",
                "update",
                "--help",
            ]
        ),
        SessionHandoffHelp(
            command: updateCommand,
            arguments: [
                "plugin",
                "update",
                "--help",
            ]
        ),
    ]

    static func getPreparation(own: String, in world: PluginWorld) -> SessionHandoffUpdatePreparation {
        let target: SessionHandoffTarget
        switch SessionHandoffTargets.find(in: world) {
        case .failure(let refusal): return .refused(refusal)
        case .success(let found): target = found
        }
        if let refusal = findHelpRefusal(target, in: world) { return .refused(refusal) }
        let face = SessionHandoffSteps.findReading(of: target, in: world).face
        guard let offer = face.findOffer(own: own) else { return .settled(face) }

        return .ready(SessionHandoffUpdatePlan(target: target, installed: offer.installed, own: own), face)
    }

    static func findHelpRefusal(_ target: SessionHandoffTarget, in world: PluginWorld) -> SessionHandoffRefusal? {
        for help in helps {
            let outcome = world.run(target.createLine(help.arguments, seconds: SessionHandoffTargets.commandSeconds))
            if let trouble = outcome.trouble {
                return .cliDidNotAnswer(command: help.command + " --help", reason: trouble)
            }
            let text = (outcome.stdoutText ?? "") + (String(bytes: outcome.stderr, encoding: .utf8) ?? "")
            guard text.contains("--json") else {
                return .cliTooOld(path: target.cli, command: help.command, option: "--json")
            }
        }

        return nil
    }

    static func getChange(_ plan: SessionHandoffUpdatePlan, in world: PluginWorld) -> SessionHandoffReport {
        let before = SessionHandoffSteps.findReading(of: plan.target, in: world).face
        guard before.findOffer(own: plan.own)?.installed == plan.installed else {
            return SessionHandoffReport(
                title: SessionHandoffUpdateCopy.notUpdatedTitle,
                text: SessionHandoffUpdateCopy.getChangedMeanwhile(before),
                face: before
            )
        }
        let seconds = SessionHandoffSteps.installSeconds
        let refreshed = world.run(plan.target.createLine(refreshArguments, seconds: seconds))
        var answer = SessionHandoffListing.getAnswer(of: refreshed)
        var command = refreshCommand
        if answer.isDone {
            let updated = world.run(plan.target.createLine(updateArguments, seconds: seconds))
            answer = SessionHandoffListing.getUpdateAnswer(of: updated)
            command = updateCommand
        }
        let after = SessionHandoffSteps.findReading(of: plan.target, in: world).face

        return getReport(plan, answer: answer, command: command, after: after)
    }

    static func getReport(
        _ plan: SessionHandoffUpdatePlan,
        answer: PluginChangeAnswer,
        command: String,
        after: SessionHandoffFace
    ) -> SessionHandoffReport {
        guard case .installed(let version?, .none, let isEnabled, _) = after,
              let listed = PluginVersion(version),
              let before = PluginVersion(plan.installed),
              let own = PluginVersion(plan.own),
              listed >= before else {
            return SessionHandoffUpdateCopy.getUnsettled(answer, command: command, after: after)
        }
        let caveat = answer.isDone ? nil : "\(command) did not answer cleanly (\(answer.message))"
        guard listed > before else {
            return SessionHandoffReport(
                title: SessionHandoffUpdateCopy.notUpdatedTitle,
                text: SessionHandoffUpdateCopy.getNotUpdated(
                    listed: version,
                    own: plan.own,
                    caveat: caveat
                ),
                face: after
            )
        }

        return SessionHandoffReport(
            title: SessionHandoffUpdateCopy.updatedTitle,
            text: SessionHandoffUpdateCopy.getUpdated(
                listed: version,
                own: listed < own ? plan.own : nil,
                caveat: caveat,
                isEnabled: isEnabled
            ),
            face: after
        )
    }
}
