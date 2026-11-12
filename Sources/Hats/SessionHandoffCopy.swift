import Foundation

enum SessionHandoffCopy {
    static func getText(_ refusal: SessionHandoffRefusal) -> String {
        switch refusal {
        case .sessionsUnreadable:
            return "The list of running Claude Code sessions could not be read, so Hats cannot tell which Claude "
                + "Code and which settings folder they use. Try again in a moment."
        case .sessionsDisagree(let folders):
            return "The running Claude Code sessions use different settings folders — "
                + folders.joined(separator: ", ") + " — so there is no single place to install into. Quit the "
                + "sessions that do not use the folder you work with, then try again."
        case .sessionsDisagreeOnVariables(let names):
            return "The running Claude Code sessions share a settings folder but differ in "
                + names.joined(separator: ", ") + ", so they would not read the plugin the same way. Quit the "
                + "sessions started with other values, then try again."
        case .relativeConfigFolder(let value):
            return "CLAUDE_CONFIG_DIR is set to \(value), which is not a full path, so it names a different "
                + "folder for every folder Claude Code starts in. Set it to a path that starts with /, then try again."
        case .noConfigFolder(let path):
            return "Claude Code's settings folder \(path) does not exist. Start Claude Code once so it creates "
                + "the folder, then try again."
        case .noCLI:
            return "Claude Code was not found: no running session named it, and none answered in /opt/homebrew/bin, "
                + "/usr/local/bin, ~/.local/bin, ~/.claude/local or on the PATH Hats was started with. Install "
                + "Claude Code, or start a session, then try again."
        case .pythonMissing(let place):
            return "The plugin runs python3, and none was found in \(place). Install Python 3 — the Xcode Command "
                + "Line Tools bring one: xcode-select --install — then try again."
        case .pythonPlaceholder(let path):
            return "The plugin runs python3, and \(path) is only the placeholder macOS keeps until the Xcode Command "
                + "Line Tools are installed: starting it would open their installer. Install them with "
                + "xcode-select --install in Terminal, then try again."
        case .pythonUnchecked(let reason):
            return "Hats could not check python3: \(reason). Try again in a moment."
        case .oldHook(let file, let commands):
            return "\(file) already starts the handoff hook by itself:\n\n" + commands.joined(separator: "\n")
                + "\n\nWith the plugin as well, every session would start it twice. Remove that entry from "
                + "hooks › SessionStart in that file — and its group, if nothing else is left in it — then press "
                + "Install again. Hats does not edit that file."
        case .brokenSettings(let file, let reason):
            return "\(file) could not be read as JSON: \(reason). Claude Code records the plugin in that file and "
                + "would fail too. Fix the file, then try again. Hats does not edit it."
        case .cliTooOld(let path):
            return "The Claude Code at \(path) is too old: its claude plugin install has no --marketplace option. "
                + "Update Claude Code (claude update), then try again."
        case .cliDidNotAnswer(let command, let reason):
            return "\(command) did not answer: \(reason). Nothing was changed."
        case .notOurs(let reason):
            return "\(reason). Hats changes nothing while that is so."
        }
    }

    static func getListTrouble(_ read: Result<[PluginRecord], SessionHandoffTrouble>) -> String {
        guard case .failure(let trouble) = read else { return "" }
        return "The plugin list of Claude Code could not be read: \(trouble.text)."
    }

    static func getSourceTrouble(_ read: Result<[MarketplaceRecord], SessionHandoffTrouble>) -> String {
        guard case .failure(let trouble) = read else { return "" }
        return "Where a plugin named hats would come from could not be told — the marketplace list of Claude Code "
            + "could not be read: \(trouble.text)."
    }

    static func getChangedMeanwhile(_ face: SessionHandoffFace) -> String {
        "Nothing was installed: the plugin list changed while the window was open. " + getStatus(face)
    }

    static func getNotReached(_ command: String, after: SessionHandoffFace) -> String {
        "\(command) answered ok, but the plugin list now reads: " + getStatus(after)
    }

    static func getReachedAnyway(_ command: String, answer: String, after: SessionHandoffFace) -> String {
        "\(command) did not answer cleanly (\(answer)), but the plugin list now reads: " + getStatus(after)
    }

    static func getStatus(_ face: SessionHandoffFace) -> String {
        switch face {
        case .unread:
            return "Not checked yet."
        case .notInstalled(let elsewhere):
            return "Not installed. The plugin hands a saved resume note to the next Claude Code session."
                + getElsewhere(elsewhere)
        case .installed(let version, let folder, let isEnabled, let elsewhere):
            let numbered = version.map { " (version \($0))" } ?? ""
            let from = folder.map { " from the folder \($0)" } ?? " from github.com/\(SessionHandoffProvenance.repository)"
            let off = isEnabled ? "" : " It is switched off in Claude Code: turn it on with claude plugin enable "
                + "\(SessionHandoffProvenance.pluginID) --scope user."
            return "Installed\(numbered)\(from).\(off)" + getElsewhere(elsewhere)
        case .notOurs(let reason):
            return "\(reason). Hats leaves it alone."
        case .unknown(let reason):
            return reason
        }
    }

    static func getElsewhere(_ records: [PluginRecord]) -> String {
        guard !records.isEmpty else { return "" }
        let places = records.map { record in
            "\(record.scope) scope" + (record.projectPath.map { " in \($0)" } ?? "")
        }

        return " Also installed at " + places.joined(separator: ", ") + " — Hats does not touch that."
    }
}
