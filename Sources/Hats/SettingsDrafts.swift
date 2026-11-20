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
    var gatewayPort: Int?
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

    func canApply(in settings: AppSettings) -> Bool {
        let states = SettingsField.allCases.map { getState($0, in: settings) }

        return !states.contains(where: \.isRefusedDraft) && states.contains { $0.applicable != nil }
    }

    func hasPending(in settings: AppSettings) -> Bool {
        SettingsField.allCases.map { getState($0, in: settings) }
            .contains { $0.isRefusedDraft || $0.applicable != nil }
    }

    func getChanges(in settings: AppSettings) -> SettingsChanges? {
        guard canApply(in: settings) else { return nil }
        let value = { (field: SettingsField) in self.getState(field, in: settings).applicable }
        var changes = SettingsChanges()
        changes.contextThresholds = getContext(in: settings, value: value)
        changes.limitThresholds = getLimits(in: settings, value: value)
        changes.autoSwitch = getAutoSwitch(in: settings, value: value)
        changes.gatewayPort = value(.port)
        changes.gatewaySettleSeconds = value(.settle)

        return changes
    }

    func apply(_ model: HatsModel) {
        guard let changes = getChanges(in: model.snapshot.settings) else { return }
        Self.send(changes, to: model.actions)
        let port = model.snapshot.settings.gatewayPort
        drafts = drafts.filter { field, _ in
            field == .port && changes.gatewayPort.map { $0 != port } == true
        }
    }

    static func send(_ changes: SettingsChanges, to actions: HatsActions?) {
        if let seconds = changes.gatewaySettleSeconds { actions?.applyGatewaySettle(seconds) }
        if let port = changes.gatewayPort { actions?.applyGatewayPort(port) }
        if let policy = changes.autoSwitch { actions?.updateAutoSwitch(policy) }
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

    private func getAutoSwitch(in settings: AppSettings, value: (SettingsField) -> Int?) -> AutoSwitchPolicy? {
        let session = value(.sessionSwitch)
        let weekly = value(.weeklySwitch)
        guard session != nil || weekly != nil else { return nil }
        var next = settings.autoSwitch
        next.sessionThresholdPercent = session ?? next.sessionThresholdPercent
        next.weeklyThresholdPercent = weekly ?? next.weeklyThresholdPercent

        return next
    }
}
