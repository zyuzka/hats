import Foundation

extension HatsCopy {
    static let warnAt = "Warn at"
    static let anchorAt = "Anchor at"
    static let afterAnchoring = "After anchoring"
    static let contextThresholdsNote =
        "Needs the session handoff plugin, with mods on in Claude Code 2.1.323 or later. A session is told "
            + "once per threshold, again after its context gets smaller; an idle session hears of it with its "
            + "next message. A session already past the lower threshold at its first answer gets neither."
    static let drainBackgroundWork = "Drain background work"
    static let drainNote =
        "From the warning on, new subagents, workflows, monitors and background commands are refused. Not refused: "
            + "a command Claude Code moves to the background itself, after its time limit, and a skill that runs in "
            + "the background — both are waited for; a command detached with & or nohup is neither waited for nor "
            + "listed. At the anchor threshold the session waits for running work up to this long, then anchors and "
            + "lists what still runs. A monitor on a socket and a teammate are listed, not waited for."

    static func getAfterSaveTitle(_ action: AfterSave) -> String {
        switch action {
        case .tell:
            return "Only tell me"
        case .offerClear:
            return "Tell me and offer /clear"
        case .offerExit:
            return "Tell me and offer /exit and a new session"
        case .clear:
            return "Clear and go on from the note"
        }
    }

    static func getDrainWaitTitle(minutes: Int) -> String {
        "Wait up to \(minutes) min"
    }

    static func getContextNoticeTitle(label: String, percent: Int) -> String {
        "\(label) — context \(percent)%"
    }

    static func getWarnNoticeBody(warn: Int, save: Int?) -> String {
        let warned = "Past the warning threshold of \(warn)%."
        guard let save else { return warned }

        return "\(warned) The session anchors at \(save)%."
    }

    static func getAnchorNoticeBody(save: Int, drainMinutes: Int?) -> String {
        let past = "Past \(save)%: the session anchors at the end of its turn"
        guard let drainMinutes else { return "\(past)." }

        return "\(past), after its background work (up to \(drainMinutes) min)."
    }

    static func getClearNoticeBody(save: Int, drainMinutes: Int?) -> String {
        let past = "Past \(save)%: the session anchors at the end of its turn"
        let clear = "if nothing stands in the way, clears its context and goes on from its note."
        guard let drainMinutes else { return "\(past) and, \(clear)" }

        return "\(past), after its background work (up to \(drainMinutes) min), and, \(clear)"
    }
}
