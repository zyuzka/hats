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
    let browser: String?
    let loginValidity: String?
    let loginAction: String

    init(
        hat: Account,
        isWearing: Bool,
        usage: UsageReading?,
        usageTrouble: UsageTrouble?,
        roseWhileParked: Int? = nil,
        chromeNames: [String: String] = [:],
        now: Date = Date()
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
        browser = hat.browser?.label(chromeNames: chromeNames)
        loginValidity = HatsCopy.loginValidity(for: hat, now: now)
        loginAction = hat.hasStoredCredentials ? "Log in again…" : "Log in…"
    }
}

enum SessionsState: Equatable {
    case unknown
    case counted([Session])

    var count: Int? {
        if case .counted(let live) = self { return live.count }
        return nil
    }
}

struct HatsSnapshot: Equatable {
    var header: String = ""
    var tool: Tool = .claudeCode
    var rows: [HatRowState] = []
    var sessions: SessionsState = .unknown
    var gatewaySessions: [GatewaySessionRow] = []
    var horizon: String = ""
    var gateway: GatewayProcess.Status = .notRunning
    var environment: GatewayEnvironmentReport?
    var settings = AppSettings()
    var banner: AutoSwitchRecord?
    var bannerFromTitle: String = ""
    var version: String = "dev"
    var changing: String?
    var startAtLogin = LoginItem.face(for: .notRegistered)
    var retiredPort: Int?
    var portRefusal: String?
    var everySession: [Session]?
    var reducesMotion = false

    var wearing: HatRowState? { rows.first(where: \.isWearing) }

    var menuBarTitle: String {
        guard settings.showsHatNameInTheMenuBar, let worn = wearing else { return "" }
        return " " + worn.title
    }

    var gatewayAddresses: GatewayAddresses {
        .of(currentPort: settings.gatewayPort, retiredPort: retiredPort)
    }

    var menuBarAccessibilityLabel: String {
        guard let worn = wearing else { return "Hats — no hat on" }
        return "Hats — wearing \(worn.title)"
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

    func title(of id: String) -> String { rows.first { $0.id == id }?.title ?? id }
}

protocol HatsActions: AnyObject {
    func wear(_ id: String)
    func addHat()
    func relogin(_ id: String)
    func rename(_ id: String)
    func chooseBrowser(_ id: String)
    func remove(_ id: String)
    func setGateway(enabled: Bool)
    func applyGatewayPort(_ port: Int)
    func applyGatewaySettle(_ seconds: Int)
    func restartGateway()
    func takeOverProfile()
    func keepMyProfile()
    func copyVariables()
    func openLog()
    func updateAutoSwitch(_ policy: AutoSwitchPolicy)
    func switchBack()
    func openSessions()
    func showSettings()
    func checkForUpdates()
    func showReleases()
    func toggleStartAtLogin()
    func toggleHatNameInTheMenuBar()
    func toggleTheBlinkingCursor()
    func quit()
}

final class HatsModel: ObservableObject {
    @Published var snapshot = HatsSnapshot()
    weak var actions: HatsActions?
}
