import Foundation

extension SettingsDrafts {
    static func getStored(_ field: SettingsField, in settings: AppSettings) -> Int? {
        switch field {
        case .contextWarn: return settings.contextThresholds.warnPercent
        case .contextSave: return settings.contextThresholds.savePercent
        case .limitWarn: return settings.limitThresholds.warnPercent
        case .limitSave: return settings.limitThresholds.savePercent
        case .sessionSwitch: return settings.autoSwitch.sessionThresholdPercent
        case .weeklySwitch: return settings.autoSwitch.weeklyThresholdPercent
        case .port: return settings.gatewayPort
        case .settle: return settings.gatewaySettleSeconds
        case .codexSessionSwitch: return settings.codexAutoSwitch.sessionThresholdPercent
        case .codexWeeklySwitch: return settings.codexAutoSwitch.weeklyThresholdPercent
        case .codexPort: return settings.codexGatewayPort
        }
    }

    func getText(_ field: SettingsField, in settings: AppSettings) -> String {
        if let draft = getDraft(field, in: settings) { return draft.text }

        return Self.getStored(field, in: settings).map(String.init) ?? ""
    }

    func getState(_ field: SettingsField, in settings: AppSettings, note: String? = nil) -> SettingsFieldState {
        let text = getText(field, in: settings)
        let isDraft = getDraft(field, in: settings) != nil
        guard let current = Self.getStored(field, in: settings) else {
            return SettingsFieldState(text: text, reason: note, applicable: nil, isRefusedDraft: false)
        }
        if let plain = Self.getPlainField(field) {
            let decision = TypedNumber.getRangeDecision(text, current: current, range: Self.getRange(plain))
            return Self.getState(text, decision: decision, isDraft: isDraft, reason: HatsCopy.getRangeRefusal(plain))
        }
        let bounds = getBounds(field, in: settings)
        let decision = TypedNumber.getPercentDecision(text, current: current, bounds: bounds)
        let shown = TypedNumber.getPercentFieldState(text, current: current, bounds: bounds, note: note)
        if case .refuse = decision {
            return SettingsFieldState(text: text, reason: shown.reason, applicable: nil, isRefusedDraft: isDraft)
        }

        return SettingsFieldState(text: text, reason: shown.reason, applicable: shown.applicable, isRefusedDraft: false)
    }

    func getBounds(_ field: SettingsField, in settings: AppSettings) -> PercentBounds {
        switch field {
        case .contextWarn: return settings.contextThresholds.getWarnBounds()
        case .contextSave: return settings.contextThresholds.getSaveBounds()
        case .limitWarn: return settings.limitThresholds.getWarnBounds()
        case .limitSave: return settings.limitThresholds.getSaveBounds()
        case .sessionSwitch, .weeklySwitch, .codexSessionSwitch, .codexWeeklySwitch:
            return PercentBounds(AutoSwitchPolicy.thresholdRange)
        case .port, .codexPort:
            return PercentBounds(Self.getRange(.port))
        case .settle:
            return PercentBounds(Self.getRange(.settle))
        }
    }

    static func getPlainField(_ field: SettingsField) -> PlainSettingsField? {
        switch field {
        case .contextWarn, .contextSave, .limitWarn, .limitSave, .sessionSwitch, .weeklySwitch,
             .codexSessionSwitch, .codexWeeklySwitch: return nil
        case .port, .codexPort: return .port
        case .settle: return .settle
        }
    }

    static func getRange(_ field: PlainSettingsField) -> ClosedRange<Int> {
        switch field {
        case .port: return AppSettings.portRange
        case .settle: return AppSettings.settleRange
        }
    }

    private static func getState(
        _ text: String,
        decision: PercentDecision,
        isDraft: Bool,
        reason: String
    ) -> SettingsFieldState {
        switch decision {
        case .silent:
            return SettingsFieldState(text: text, reason: nil, applicable: nil, isRefusedDraft: false)
        case .apply(let value):
            return SettingsFieldState(text: text, reason: nil, applicable: value, isRefusedDraft: false)
        case .refuse:
            return SettingsFieldState(text: text, reason: reason, applicable: nil, isRefusedDraft: isDraft)
        }
    }

    private func getDraft(_ field: SettingsField, in settings: AppSettings) -> SettingsDraft? {
        guard let draft = drafts[field], draft.over == Self.getStored(field, in: settings) else { return nil }

        return draft
    }
}
