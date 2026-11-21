import Foundation

struct SettingsLeftover: Equatable {
    let name: String
    let text: String
    let reason: String
}

extension SettingsDrafts {
    static let notApplied = "was not applied"

    func getLeftovers(in settings: AppSettings) -> [SettingsLeftover] {
        SettingsField.allCases.compactMap { field in
            let state = getState(field, in: settings)
            if state.isRefusedDraft {
                return SettingsLeftover(name: Self.getName(field), text: state.text, reason: state.reason ?? "")
            }
            guard state.applicable != nil else { return nil }

            return SettingsLeftover(name: Self.getName(field), text: state.text, reason: Self.notApplied)
        }
    }

    static func getName(_ field: SettingsField) -> String {
        switch field {
        case .contextWarn: return "Context \(HatsCopy.warnAt)"
        case .contextSave: return "Context \(HatsCopy.anchorAt)"
        case .limitWarn: return "\(HatsCopy.hatLimit) \(HatsCopy.warnAt)"
        case .limitSave: return "\(HatsCopy.hatLimit) \(HatsCopy.anchorAt)"
        case .sessionSwitch: return "\(Tool.claudeCode.displayName) auto-switch on the 5-hour limit"
        case .weeklySwitch: return "\(Tool.claudeCode.displayName) auto-switch on the weekly limit"
        case .codexSessionSwitch: return "\(Tool.codex.displayName) auto-switch on the 5-hour limit"
        case .codexWeeklySwitch: return "\(Tool.codex.displayName) auto-switch on the weekly limit"
        case .port: return "Gateway port"
        case .settle: return "Settle"
        case .codexPort: return "Codex gateway port"
        }
    }
}
