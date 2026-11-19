import Foundation

enum CodexPluginPrompts {
    static func create(_ plan: CodexPluginPlan, own: String) -> HatPrompt {
        let commands = plan.commands.map { "codex " + $0.joined(separator: " ") }.joined(separator: "\n")
        let text = "Hats will run, with the Codex at \(plan.target.cli) and CODEX_HOME=\(plan.target.codexHome):\n"
            + commands + "\n\n" + getMeaning(plan, own: own)

        return HatPrompt(
            title: getTitle(plan.action),
            text: text,
            buttons: [
                getButton(plan.action),
                "Cancel",
            ]
        )
    }

    static func getTitle(_ action: CodexPluginAction) -> String {
        switch action {
        case .install: return "Install the Codex plugin?"
        case .update: return "Update the Codex plugin?"
        case .refresh: return "Refresh the Codex plugin?"
        case .remove: return "Remove the Codex plugin?"
        }
    }

    static func getButton(_ action: CodexPluginAction) -> String {
        switch action {
        case .install: return "Install"
        case .update: return "Update"
        case .refresh: return "Refresh"
        case .remove: return "Remove"
        }
    }

    static func getMeaning(_ plan: CodexPluginPlan, own: String) -> String {
        let id = CodexPluginProvenance.pluginID
        switch plan.action {
        case .install:
            let market = plan.commands.count > 1
                ? "The first adds the marketplace hats from github.com/\(CodexPluginProvenance.repository); the "
                    + "second installs \(id) from it. "
                : "It installs \(id) from the marketplace hats Codex already lists. "
            return market + "The plugin asks Codex to save a resume note before it compacts the context window and "
                + "hands the note back after the compaction. " + CodexPluginText.trustNote
        case .update:
            return "The first refreshes Codex's copy of the marketplace hats from "
                + "github.com/\(CodexPluginProvenance.repository); the second installs \(id) again from it, "
                + "from version \(plan.installed ?? "?") to the version GitHub offers now; this Hats comes with "
                + "\(own). " + CodexPluginText.trustNote
        case .refresh:
            return "It copies \(id) again from the folder the marketplace hats points at, so Codex runs the files "
                + "that are in the folder now. " + CodexPluginText.trustNote
        case .remove:
            return "It removes \(id) and Codex's copy of it. The marketplace hats stays, and so do your resume notes."
        }
    }
}
