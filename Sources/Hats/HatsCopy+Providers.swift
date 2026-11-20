import Foundation

extension HatsCopy {
    static func providerAverage(_ summary: ProviderSummary) -> String {
        "5h " + averageText(summary.session) + " · week " + averageText(summary.week)
    }

    private static func averageText(_ average: ProviderAverage) -> String {
        let main = average.withoutVacation.map { "\($0)%" } ?? "–"
        guard let all = average.withVacation else { return main }

        return main + " (\(all)%)"
    }

    static func tab(_ tool: Tool, averages summary: ProviderSummary) -> String {
        let session = summary.session.withoutVacation
        let week = summary.week.withoutVacation
        guard session != nil || week != nil else { return tab(tool) }
        let shown = { (percent: Int?) in percent.map { "\($0)%" } ?? "–" }

        return tab(tool) + " " + shown(session) + " · " + shown(week)
    }

    static func tab(_ tool: Tool) -> String {
        switch tool {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        }
    }

    static func noHats(on tool: Tool) -> String { "No \(tab(tool)) hats yet" }

    static func noHatsHint(on tool: Tool) -> String {
        "Press + below (Add hat…) to name a \(tab(tool)) account. Hats keeps its login ready to put on."
    }

    static func noHatOn(_ tool: Tool) -> String { "No \(tab(tool)) hat on" }
}
