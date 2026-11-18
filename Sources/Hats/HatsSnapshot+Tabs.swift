import Foundation

extension HatsSnapshot {
    func rows(of tool: Tool) -> [HatRowState] {
        switch tool {
        case .claudeCode: return rows
        case .codex: return codexRows
        }
    }

    func wearing(on tool: Tool) -> HatRowState? { rows(of: tool).first(where: \.isWearing) }

    func headerTitle(on tool: Tool) -> String {
        if let worn = wearing(on: tool) { return worn.title }

        return tool == .claudeCode ? header : HatsCopy.noHatOn(tool)
    }
}
