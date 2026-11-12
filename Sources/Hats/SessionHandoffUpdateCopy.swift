import Foundation

struct SessionHandoffReport: Equatable {
    let title: String
    let text: String
    let face: SessionHandoffFace?
}

enum SessionHandoffUpdateCopy {
    static let updatedTitle = "The plugin was updated"
    static let notUpdatedTitle = "The plugin was not updated"
    static let unconfirmedTitle = "The update could not be confirmed"
    static let reloadNote = "Running sessions get the new version after /reload-plugins; new sessions get it when "
        + "they start."
    static let offNote = "It is still switched off in Claude Code, as it was: turn it on with claude plugin enable "
        + "\(SessionHandoffProvenance.pluginID) --scope user."

    static func getChangedMeanwhile(_ face: SessionHandoffFace) -> String {
        "Nothing was updated: the plugin list changed while the window was open. " + SessionHandoffCopy.getStatus(face)
    }

    static func getUpdated(
        listed: String,
        own: String?,
        caveat: String?,
        isEnabled: Bool
    ) -> String {
        let reached = own.map { "Updated to \(listed); this Hats comes with \($0), which GitHub does not offer yet." }
            ?? "Updated to \(listed)."
        let parts = [
            reached,
            caveat.map { "\($0), but the plugin list shows \(listed)." },
            reloadNote,
            isEnabled ? nil : offNote,
        ]

        return parts.compactMap { $0 }.joined(separator: " ")
    }

    static func getNotUpdated(
        listed: String,
        own: String,
        caveat: String?
    ) -> String {
        let reason = caveat.map { "\($0)." } ?? "GitHub may not offer it yet."

        return "Not updated: Claude Code still lists \(listed), and this Hats comes with \(own). " + reason
    }

    static func getUnsettled(
        _ answer: PluginChangeAnswer,
        command: String,
        after: SessionHandoffFace
    ) -> SessionHandoffReport {
        let said = answer.isDone
            ? "\(command) answered ok. "
            : "\(command) did not answer cleanly (\(answer.message)). "
        guard case .unknown(let reason) = after else {
            return SessionHandoffReport(
                title: notUpdatedTitle,
                text: said + "The plugin list now reads: " + SessionHandoffCopy.getStatus(after),
                face: after
            )
        }

        return SessionHandoffReport(
            title: unconfirmedTitle,
            text: said + reason + " Hats cannot tell whether the plugin was updated.",
            face: after
        )
    }
}
