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
        var context = settings.contextThresholds
        var limits = settings.limitThresholds
        let isTyped = getDraft(field, in: settings) != nil
        switch field {
        case .contextWarn:
            context.savePercent = getFinal(.contextSave, in: settings, within: ContextThresholds.saveRange, isTyped)
            return context.getWarnBounds()
        case .contextSave:
            context.warnPercent = getFinal(.contextWarn, in: settings, within: ContextThresholds.warnRange, isTyped)
            return context.getSaveBounds()
        case .limitWarn:
            limits.savePercent = getFinal(.limitSave, in: settings, within: LimitThresholds.range, isTyped)
            return limits.getWarnBounds()
        case .limitSave:
            limits.warnPercent = getFinal(.limitWarn, in: settings, within: LimitThresholds.range, isTyped)
            return limits.getSaveBounds()
        case .sessionSwitch, .weeklySwitch:
            return PercentBounds(AutoSwitchPolicy.thresholdRange)
        case .port:
            return PercentBounds(Self.getRange(.port))
        case .settle:
            return PercentBounds(Self.getRange(.settle))
        }
    }

    static func getPlainField(_ field: SettingsField) -> PlainSettingsField? {
        switch field {
        case .contextWarn, .contextSave, .limitWarn, .limitSave, .sessionSwitch, .weeklySwitch: return nil
        case .port: return .port
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

    private func getFinal(
        _ field: SettingsField,
        in settings: AppSettings,
        within range: ClosedRange<Int>,
        _ isTyped: Bool
    ) -> Int? {
        guard let stored = Self.getStored(field, in: settings) else { return nil }
        guard isTyped,
              let draft = getDraft(field, in: settings),
              let typed = TypedNumber.typed(draft.text),
              range.contains(typed)
        else { return stored }

        return typed
    }
}
