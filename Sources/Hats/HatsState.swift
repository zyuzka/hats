import Foundation

struct HatRowState: Identifiable, Equatable {
    let id: String
    let title: String
    let address: String
    let isWearing: Bool
    let isSwitchable: Bool
    let blocker: String?
    let identityTrouble: String?
    let expiry: String?
    let usage: UsageReading?
    let usageTrouble: UsageTrouble?
    let roseWhileParked: Int?
    let week: String?
    let weekSighting: WeekSighting?
    let weekSpoken: String?
    let browser: String?
    let loginValidity: String?
    let loginAction: String
    let isOnVacation: Bool
    let tool: Tool

    init(
        hat: Account,
        isWearing: Bool,
        usage: UsageReading?,
        usageTrouble: UsageTrouble?,
        roseWhileParked: Int? = nil,
        week: WeekSighting? = nil,
        chromeNames: [String: String] = [:],
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) {
        id = hat.id
        title = hat.title
        address = hat.email
        self.isWearing = isWearing
        isSwitchable = hat.blocker(at: now) == nil
        blocker = HatsCopy.blocker(for: hat, now: now)
        identityTrouble = hat.identityDisagreement.map { HatsCopy.identityDisagreement($0) }
        expiry = HatsCopy.expiry(for: hat, now: now)
        self.usage = usage
        self.usageTrouble = usageTrouble
        self.roseWhileParked = roseWhileParked
        weekSighting = week
        self.week = week.map {
            HatsCopy.weekLine(
                percent: $0.window.percent,
                resetsAt: $0.window.resetsAt,
                isConfirmed: $0.isConfirmed,
                timeZone: timeZone,
                now: now
            )
        }
        weekSpoken = week.map {
            HatsCopy.getWeekSpoken(
                percent: $0.window.percent,
                resetsAt: $0.window.resetsAt,
                isConfirmed: $0.isConfirmed,
                timeZone: timeZone,
                now: now
            )
        }
        browser = hat.browser?.label(chromeNames: chromeNames)
        loginValidity = HatsCopy.loginLine(for: hat, isWorn: isWearing, now: now)
        loginAction = HatsCopy.loginAction(for: hat)
        isOnVacation = hat.vacationSince != nil
        tool = hat.wornTool
    }

    var isSkippedByTheSwitch: Bool { isOnVacation && !isWearing }
}

struct HatsSnapshot: Equatable {
    var header: String = ""
    var tool: Tool = .claudeCode
    var rows: [HatRowState] = []
    var codexRows: [HatRowState] = []
    var sessions: SessionsState = .unknown
    var gatewaySessions: [GatewaySessionRow] = []
    var horizon: String = ""
    var gateway: GatewayProcess.Status = .notRunning
    var hasFullDiskAccess = true
    var environment: GatewayEnvironmentReport?
    var settings = AppSettings()
    var banner: AutoSwitchRecord?
    var bannerFromTitle: String = ""
    var codexBanner: AutoSwitchRecord?
    var codexBannerFromTitle: String = ""
    var version: String = "dev"
    var canCheckForUpdates: Bool?
    var checksForUpdatesAutomatically: Bool?
    var hasAnUpdateWaiting = false
    var changing: String?
    var startAtLogin = LoginItem.face(for: .notRegistered)
    var retiredPort: Int?
    var portRefusal: String?
    var everySession: [Session]?
    var reducesMotion = false
    var autoSwitchWarning: AutoSwitchWarning?
    var codexAutoSwitchWarning: AutoSwitchWarning?
    var sessionHandoff = SessionHandoffRow()
    var codexPlugin = CodexPluginRow()
    var contextRows: [ContextRow] = []
    var codexGateway = CodexGatewayFace()

    var wearing: HatRowState? { rows.first(where: \.isWearing) }

    var checkForUpdatesTitle: String {
        hasAnUpdateWaiting ? "Install the waiting update\u{2026}" : "Check for Updates\u{2026}"
    }

    mutating func setUpdates(from updater: AppUpdater?) {
        canCheckForUpdates = updater?.canCheckNow
        checksForUpdatesAutomatically = updater?.checksAutomatically
        hasAnUpdateWaiting = updater?.hasAnUpdateWaiting ?? false
    }

    var menuBarTitle: String {
        guard settings.showsHatNameInTheMenuBar, let worn = wearing else { return "" }
        return " " + worn.title
    }

    var gatewayAddresses: GatewayAddresses {
        .of(currentPort: settings.gatewayPort, retiredPort: retiredPort)
    }

    var menuBarAccessibilityLabel: String {
        guard let worn = wearing else { return "Hats — no hat on" }
        guard let warning = warningAboutTheWornHat else { return "Hats — wearing \(worn.title)" }
        return "Hats — wearing \(worn.title), \(warning.menuBarLabel)"
    }

    func sessionsThrough(port: Int) -> Int? {
        guard let everySession else { return nil }
        return GatewayRetirement.dependants(on: port, among: everySession).count
    }

    var readingByHat: [String: UsageReading] {
        Dictionary(rows.compactMap { row in row.usage.map { (row.id, $0) } },
                   uniquingKeysWith: { _, last in last })
    }

    var nextInLine: String? {
        settings.autoSwitch.nextHat(after: wearing?.id,
                                    among: AutoSwitchEngine.eligible(in: rows),
                                    readings: readingByHat)
    }

    var isEveryOtherHatOnVacation: Bool { Self.isEveryOtherHatOnVacation(in: rows) }

    static func isEveryOtherHatOnVacation(in rows: [HatRowState]) -> Bool {
        let others = rows.filter { !$0.isWearing }

        return !others.isEmpty && others.allSatisfy(\.isSkippedByTheSwitch)
    }

    var hasABlockedHatInPlay: Bool { !AutoSwitchEngine.blocked(in: rows).isEmpty }

    func title(of id: String) -> String { (rows + codexRows).first { $0.id == id }?.title ?? id }
}
