import Foundation

enum SessionHandoffPrompts {
    static func createInstall(_ plan: SessionHandoffPlan) -> HatPrompt {
        let from = plan.folder.map { "the folder \($0)" } ?? "github.com/\(SessionHandoffProvenance.repository)"
        let pythonNote = plan.python.isFromTheLoginShell
            ? " — found the way a new login shell finds it, so a session started another way may find another one"
            : ""
        let text = "Hats will run, with the Claude Code at \(plan.target.cli):\nclaude "
            + plan.arguments.joined(separator: " ") + "\n\n"
            + "It installs the Claude Code plugin \(SessionHandoffProvenance.pluginID) from \(from) for your "
            + "user, recorded in the settings folder \(plan.target.configFolder). The plugin adds the anchor "
            + "command (/hats:anchor), which saves a resume note, and hooks that hand that note to the next "
            + "session in the same folder. With Claude Code's memory on, the notes go into the project's memory "
            + "folder, beside a resume-index.md and a line at the top of MEMORY.md.\n\n"
            + "It runs python3 from \(plan.python.path)\(pythonNote). New sessions load it; running ones after "
            + "/reload-plugins. You can remove it here at any time."

        return HatPrompt(
            title: "Install the session handoff plugin?",
            text: text,
            buttons: [
                "Install",
                "Cancel",
            ]
        )
    }

    static func createRemove() -> HatPrompt {
        let text = "Hats will run:\nclaude " + SessionHandoffSteps.removeArguments.joined(separator: " ") + "\n\n"
            + "It removes only your user installation of \(SessionHandoffProvenance.pluginID). The hats "
            + "marketplace stays, and so do your resume notes, your own steps, your hooks and your settings. "
            + "Installations for a project are not touched."

        return HatPrompt(
            title: "Remove the session handoff plugin?",
            text: text,
            buttons: [
                "Remove",
                "Cancel",
            ]
        )
    }
}
