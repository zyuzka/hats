import Foundation

struct CodexPluginReport: Equatable {
    let title: String
    let text: String
    let face: CodexPluginFace?
    let isChanged: Bool
}

enum CodexPluginText {
    static let trustNote = "When the hooks of the hats plugin are new or changed, the next Codex window you open "
        + "asks whether to trust them. Trust them there: Hats does not do it for you, and without that trust "
        + "Codex does not run them. Hooks you trusted before and that did not change are not asked about again."
    static let nothingToDoTitle = "The Codex plugin was left as it is"
    static let notFound = "Codex not found: there is no codex in /opt/homebrew/bin, /usr/local/bin, ~/.local/bin "
        + "or on the PATH of a new login shell."

    static func getDoneTitle(_ action: CodexPluginAction) -> String {
        switch action {
        case .install: return "Installed"
        case .update: return "Updated"
        case .refresh: return "Refreshed"
        case .remove: return "Removed"
        }
    }

    static func getJournalVerb(_ action: CodexPluginAction) -> String {
        switch action {
        case .install: return "installing"
        case .update: return "updating"
        case .refresh: return "refreshing"
        case .remove: return "removing"
        }
    }

    static func getFailureTitle(_ action: CodexPluginAction) -> String {
        switch action {
        case .install: return "The Codex plugin was not installed"
        case .update: return "The Codex plugin was not updated"
        case .refresh: return "The Codex plugin was not refreshed"
        case .remove: return "The Codex plugin was not removed"
        }
    }

    static func getListTrouble(_ read: Result<[CodexPluginRecord], SessionHandoffTrouble>) -> String {
        guard case .failure(let trouble) = read else { return "" }
        return "The plugin list of Codex could not be read: \(trouble.text)."
    }

    static func getMarketTrouble(_ read: Result<[CodexMarketRecord], SessionHandoffTrouble>) -> String {
        guard case .failure(let trouble) = read else { return "" }
        return "Where a plugin named hats would come from could not be told — the marketplace list of Codex "
            + "could not be read: \(trouble.text)."
    }

    static func getChangedMeanwhile(_ face: CodexPluginFace) -> String {
        "Nothing was changed: the Codex plugin list changed while the window was open. " + getStatus(face)
    }

    static func getStatus(_ face: CodexPluginFace) -> String {
        switch face {
        case .unread:
            return "Not checked yet."
        case .noCodex:
            return notFound
        case .notInstalled:
            return "Not installed. The plugin asks Codex to save a resume note before it compacts the context "
                + "window and hands the note back after the compaction."
        case .installed(let version, let isEnabled):
            let numbered = version.map { ", \($0)," } ?? ""
            let off = isEnabled ? "" : " It is switched off in Codex."
            return "Installed\(numbered) from github.com/\(CodexPluginProvenance.repository).\(off)"
        case .fromFolder(let version, let folder, let copy):
            let numbered = version.map { ", \($0)," } ?? ""
            return "Installed\(numbered) from a folder, \(folder). Hats does not update it. " + getCopyLine(copy)
        case .notOurs(let reason):
            return "Not ours: \(reason). Hats leaves it alone."
        case .unknown(let reason):
            return reason
        }
    }

    static func getCopyLine(_ copy: CodexCopyState) -> String {
        switch copy {
        case .same:
            return "Codex's copy matches the folder."
        case .differs(let reason):
            return "Codex's copy is out of date: \(reason). Refresh copies the folder again."
        case .unreadable(let reason):
            return "Hats could not compare Codex's copy with the folder: \(reason)."
        }
    }

    static func getUpdateLine(_ row: CodexPluginRow) -> (text: String, spoken: String)? {
        guard let offer = row.offer else { return nil }

        return (
            "Update available: \(offer.installed) \u{2192} \(offer.own)",
            "Update available: version \(offer.installed) is installed, and this Hats comes with version \(offer.own)"
        )
    }

    static func getReport(
        _ action: CodexPluginAction,
        isReached: Bool,
        answer: PluginChangeAnswer,
        command: String,
        after: CodexPluginFace
    ) -> CodexPluginReport {
        guard isReached else {
            let said = answer.isDone ? "\(command) answered ok" : "\(command) failed: \(answer.message)"
            return CodexPluginReport(
                title: getFailureTitle(action),
                text: said + ". The Codex plugin list now reads: " + getStatus(after),
                face: after,
                isChanged: false
            )
        }
        let parts = [
            getStatus(after),
            answer.isDone ? nil : "\(command) did not answer cleanly (\(answer.message)), but the list reads so.",
            action == .remove ? nil : trustNote,
        ]

        return CodexPluginReport(
            title: getDoneTitle(action),
            text: parts.compactMap { $0 }.joined(separator: " "),
            face: after,
            isChanged: true
        )
    }
}
