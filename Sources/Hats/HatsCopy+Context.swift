import Foundation

extension HatsCopy {
    static let warnAt = "Warn at"
    static let anchorAt = "Anchor at"
    static let afterAnchoring = "After anchoring"
    static let contextThresholdsNote =
        "Needs the session handoff plugin, with mods on in Claude Code 2.1.323 or later. A session is told "
            + "once per threshold, again after its context gets smaller; an idle session hears of it with its "
            + "next message. A session already past the lower threshold at its first answer gets neither."

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

    static func getContextNoticeTitle(label: String, percent: Int) -> String {
        "\(label) — context \(percent)%"
    }

    static func getWarnNoticeBody(warn: Int, save: Int?) -> String {
        let warned = "Past the warning threshold of \(warn)%."
        guard let save else { return warned }

        return "\(warned) The session anchors at \(save)%."
    }

    static func getAnchorNoticeBody(save: Int) -> String {
        "Past \(save)%: the session anchors at the end of its turn."
    }

    static func getClearNoticeBody(save: Int) -> String {
        "Past \(save)%: the session anchors at the end of its turn and, if nothing stands in the way, clears its "
            + "context and goes on from its note."
    }
}
