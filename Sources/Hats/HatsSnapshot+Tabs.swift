import Foundation

struct ShownSwitchBanner: Equatable {
    let record: AutoSwitchRecord
    let fromTitle: String
    let tool: Tool
}

extension HatsSnapshot {
    func rows(of tool: Tool) -> [HatRowState] {
        switch tool {
        case .claudeCode: return rows
        case .codex: return codexRows
        }
    }

    func wearing(on tool: Tool) -> HatRowState? { rows(of: tool).first(where: \.isWearing) }

    var codexNextInLine: String? {
        CodexAutoSwitch.nextHat(policy: settings.codexAutoSwitch, rows: codexRows, at: Date())
    }

    func getHandover(for row: HatRowState) -> String? {
        guard row.isWearing else { return nil }
        let (isOn, next, alone) = row.tool == .codex
            ? (settings.codexAutoSwitch.isOn, codexNextInLine, Self.isEveryOtherHatOnVacation(in: codexRows))
            : (settings.autoSwitch.isOn, nextInLine, isEveryOtherHatOnVacation)
        guard isOn else { return nil }
        guard let next else { return alone ? HatsCopy.noHandoverTheOthersAreOnVacation : nil }

        return HatsCopy.handover(to: title(of: next))
    }

    mutating func showTheBanners(of settings: AppSettings) {
        banner = settings.autoSwitchRecord.flatMap { $0.seenInPopover ? nil : $0 }
        bannerFromTitle = settings.autoSwitchRecord.map { title(of: $0.from) } ?? ""
        codexBanner = settings.codexAutoSwitchRecord.flatMap { $0.seenInPopover ? nil : $0 }
        codexBannerFromTitle = settings.codexAutoSwitchRecord.map { title(of: $0.from) } ?? ""
    }

    func banner(on tool: Tool) -> ShownSwitchBanner? {
        switch tool {
        case .claudeCode: return banner.map { ShownSwitchBanner(record: $0, fromTitle: bannerFromTitle, tool: tool) }
        case .codex:
            return codexBanner.map { ShownSwitchBanner(record: $0, fromTitle: codexBannerFromTitle, tool: tool) }
        }
    }

    func headerTitle(on tool: Tool) -> String {
        if let worn = wearing(on: tool) { return worn.title }

        return tool == .claudeCode ? header : HatsCopy.noHatOn(tool)
    }
}
