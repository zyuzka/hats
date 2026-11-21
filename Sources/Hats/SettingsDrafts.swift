import Foundation

enum SettingsField: CaseIterable, Hashable {
    case contextWarn
    case contextSave
    case limitWarn
    case limitSave
    case sessionSwitch
    case weeklySwitch
    case port
    case settle
    case codexSessionSwitch
    case codexWeeklySwitch
    case codexPort
}

enum PlainSettingsField: Equatable {
    case port
    case settle
}

struct SettingsDraft: Equatable {
    let text: String
    let over: Int?
}

struct SettingsFieldState: Equatable {
    let text: String
    let reason: String?
    let applicable: Int?
    let isRefusedDraft: Bool
}

struct SettingsChanges: Equatable {
    var contextThresholds: ContextThresholds?
    var limitThresholds: LimitThresholds?
    var autoSwitch: AutoSwitchPolicy?
    var codexAutoSwitch: AutoSwitchPolicy?
    var gatewayPort: Int?
    var codexGatewayPort: Int?
    var gatewaySettleSeconds: Int?
}

final class SettingsDrafts: ObservableObject {
    @Published private(set) var drafts: [SettingsField: SettingsDraft] = [:]

    func setText(_ text: String, of field: SettingsField, in settings: AppSettings) {
        let digits = TypedNumber.getDigits(text)
        let stored = Self.getStored(field, in: settings)
        guard digits != stored.map(String.init) else {
            drafts[field] = nil
            return
        }
        drafts[field] = SettingsDraft(text: digits, over: stored)
    }

    func reset(_ field: SettingsField) {
        drafts[field] = nil
    }

    func discardAll() {
        drafts = [:]
    }

    func prune(in settings: AppSettings) {
        let fresh = drafts.filter { field, draft in draft.over == Self.getStored(field, in: settings) }
        guard fresh != drafts else { return }
        drafts = fresh
    }

    func getChanges(_ field: SettingsField, in settings: AppSettings) -> SettingsChanges? {
        guard let applicable = getState(field, in: settings).applicable else { return nil }
        let value = { (other: SettingsField) in other == field ? applicable : nil }
        var changes = SettingsChanges()
        changes.contextThresholds = getContext(in: settings, value: value)
        changes.limitThresholds = getLimits(in: settings, value: value)
        changes.autoSwitch = getAutoSwitch(settings.autoSwitch, .sessionSwitch, .weeklySwitch, value: value)
        changes.codexAutoSwitch = getAutoSwitch(
            settings.codexAutoSwitch,
            .codexSessionSwitch,
            .codexWeeklySwitch,
            value: value
        )
        changes.gatewayPort = value(.port)
        changes.codexGatewayPort = value(.codexPort)
        changes.gatewaySettleSeconds = value(.settle)

        return changes == SettingsChanges() ? nil : changes
    }

    func apply(_ field: SettingsField, _ model: HatsModel) {
        if drafts[field]?.text.isEmpty == true {
            drafts[field] = nil
            return
        }
        guard hasWritten(field, model) else { return }
        applyPartner(of: field, model)
    }

    func applyPartner(of field: SettingsField, _ model: HatsModel) {
        guard let partner = Self.getPartner(field) else { return }
        hasWritten(partner, model)
    }

    static func getPartner(_ field: SettingsField) -> SettingsField? {
        switch field {
        case .contextWarn: return .contextSave
        case .contextSave: return .contextWarn
        case .limitWarn: return .limitSave
        case .limitSave: return .limitWarn
        case .sessionSwitch, .weeklySwitch, .port, .settle, .codexSessionSwitch, .codexWeeklySwitch,
             .codexPort: return nil
        }
    }

    @discardableResult
    private func hasWritten(_ field: SettingsField, _ model: HatsModel) -> Bool {
        guard let changes = getChanges(field, in: model.snapshot.settings) else { return false }
        Self.send(changes, to: model.actions)
        let settings = model.snapshot.settings
        switch field {
        case .port where changes.gatewayPort != settings.gatewayPort: return false
        case .codexPort where changes.codexGatewayPort != settings.codexGatewayPort: return false
        default:
            drafts[field] = nil
            return true
        }
    }

    static func send(_ changes: SettingsChanges, to actions: HatsActions?) {
        if let seconds = changes.gatewaySettleSeconds { actions?.applyGatewaySettle(seconds) }
        if let port = changes.gatewayPort { actions?.applyGatewayPort(port) }
        if let port = changes.codexGatewayPort { actions?.applyCodexGatewayPort(port) }
        if let policy = changes.autoSwitch { actions?.updateAutoSwitch(policy) }
        if let policy = changes.codexAutoSwitch { actions?.updateCodexAutoSwitch(policy) }
        if let thresholds = changes.contextThresholds { actions?.updateContextThresholds(thresholds) }
        if let limits = changes.limitThresholds { actions?.updateLimitThresholds(limits) }
    }

    private func getContext(in settings: AppSettings, value: (SettingsField) -> Int?) -> ContextThresholds? {
        let warn = value(.contextWarn)
        let save = value(.contextSave)
        guard warn != nil || save != nil else { return nil }
        var next = settings.contextThresholds
        next.warnPercent = warn ?? next.warnPercent
        next.savePercent = save ?? next.savePercent

        return ContextThresholds.isAUsablePair(warn: next.warnPercent, save: next.savePercent) ? next : nil
    }

    private func getLimits(in settings: AppSettings, value: (SettingsField) -> Int?) -> LimitThresholds? {
        let warn = value(.limitWarn)
        let save = value(.limitSave)
        guard warn != nil || save != nil else { return nil }
        var next = settings.limitThresholds
        next.warnPercent = warn ?? next.warnPercent
        next.savePercent = save ?? next.savePercent

        return LimitThresholds.isAUsablePair(warn: next.warnPercent, save: next.savePercent) ? next : nil
    }

    private func getAutoSwitch(
        _ policy: AutoSwitchPolicy,
        _ sessionField: SettingsField,
        _ weeklyField: SettingsField,
        value: (SettingsField) -> Int?
    ) -> AutoSwitchPolicy? {
        let session = value(sessionField)
        let weekly = value(weeklyField)
        guard session != nil || weekly != nil else { return nil }
        var next = policy
        next.sessionThresholdPercent = session ?? next.sessionThresholdPercent
        next.weeklyThresholdPercent = weekly ?? next.weeklyThresholdPercent

        return next
    }
}
