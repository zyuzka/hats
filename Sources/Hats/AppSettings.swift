import Foundation

enum ForeignProfileResolution: String, Codable, Equatable {
    case undecided
    case keepMine
}

enum UsageDisplay: String, Codable, Equatable, CaseIterable {
    case percent
    case bars

    var title: String {
        switch self {
        case .percent: return "Percent"
        case .bars: return "Bars"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var gatewayPort = 8787
    var isGatewayEnabled = true
    var autoSwitch = AutoSwitchPolicy()
    var autoSwitchRecord: AutoSwitchRecord?
    var foreignProfileResolution = ForeignProfileResolution.undecided
    var gatewaySettleSeconds = Int(GatewayRefusal.defaultSettle)
    var showsHatNameInTheMenuBar = true
    var blinksTheCursorInTheMenuBar = true
    var pluginVersionToldAbout: String?
    var contextThresholds = ContextThresholds()
    var limitThresholds = LimitThresholds()
    var usageDisplay = UsageDisplay.percent
    var codexGatewayPort = CodexGatewayPaths.defaultPort
    var isCodexGatewayEnabled: Bool?
    var codexGatewaySecret: String?
    var codexConfigCreatedByHats = false
    var hasToldToRestartCodexWindows = false
    var hasCodexHats = false
    var popoverTab = Tool.claudeCode
    var codexAutoSwitch = AutoSwitchPolicy()
    var codexAutoSwitchRecord: AutoSwitchRecord?

    init(gatewayPort: Int = 8787) {
        self.gatewayPort = gatewayPort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let port = try c.decodeIfPresent(Int.self, forKey: .gatewayPort) ?? 8787
        gatewayPort = Self.isAUsablePort(port) ? port : 8787
        isGatewayEnabled = try c.decodeIfPresent(Bool.self, forKey: .isGatewayEnabled) ?? true
        autoSwitch = try c.decodeIfPresent(AutoSwitchPolicy.self, forKey: .autoSwitch) ?? AutoSwitchPolicy()
        autoSwitchRecord = try c.decodeIfPresent(AutoSwitchRecord.self, forKey: .autoSwitchRecord)
        let resolution = try c.decodeIfPresent(ForeignProfileResolution.self, forKey: .foreignProfileResolution)
        foreignProfileResolution = resolution ?? .undecided
        let settle = try c.decodeIfPresent(Int.self, forKey: .gatewaySettleSeconds)
            ?? Int(GatewayRefusal.defaultSettle)
        gatewaySettleSeconds = Self.isAUsableSettle(settle) ? settle : Int(GatewayRefusal.defaultSettle)
        showsHatNameInTheMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showsHatNameInTheMenuBar) ?? true
        blinksTheCursorInTheMenuBar =
            try c.decodeIfPresent(Bool.self, forKey: .blinksTheCursorInTheMenuBar) ?? true
        pluginVersionToldAbout = try c.decodeIfPresent(String.self, forKey: .pluginVersionToldAbout)
        contextThresholds = (try? c.decodeIfPresent(ContextThresholds.self, forKey: .contextThresholds))
            ?? ContextThresholds()
        limitThresholds = (try? c.decodeIfPresent(LimitThresholds.self, forKey: .limitThresholds))
            ?? LimitThresholds()
        usageDisplay = (try? c.decodeIfPresent(UsageDisplay.self, forKey: .usageDisplay)) ?? .percent
        popoverTab = (try? c.decodeIfPresent(Tool.self, forKey: .popoverTab)) ?? .claudeCode
        try decodeTheCodexGateway(from: decoder)
    }

    private mutating func decodeTheCodexGateway(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let port = try? c.decodeIfPresent(Int.self, forKey: .codexGatewayPort)
        codexGatewayPort = port.flatMap { Self.isAUsablePort($0) ? $0 : nil } ?? CodexGatewayPaths.defaultPort
        isCodexGatewayEnabled = try? c.decodeIfPresent(Bool.self, forKey: .isCodexGatewayEnabled)
        let secret = try? c.decodeIfPresent(String.self, forKey: .codexGatewaySecret)
        codexGatewaySecret = secret.flatMap { CodexGatewayPaths.isAUsableSecret($0) ? $0 : nil }
        codexConfigCreatedByHats = (try? c.decodeIfPresent(Bool.self, forKey: .codexConfigCreatedByHats)) ?? false
        let told = try? c.decodeIfPresent(Bool.self, forKey: .hasToldToRestartCodexWindows)
        hasToldToRestartCodexWindows = told ?? false
        hasCodexHats = (try? c.decodeIfPresent(Bool.self, forKey: .hasCodexHats)) ?? false
        codexAutoSwitch = (try? c.decodeIfPresent(AutoSwitchPolicy.self, forKey: .codexAutoSwitch))
            ?? AutoSwitchPolicy()
        codexAutoSwitchRecord = try? c.decodeIfPresent(AutoSwitchRecord.self, forKey: .codexAutoSwitchRecord)
    }

    static var defaultURL: URL {
        StateDirectory.url.appendingPathComponent("settings.json")
    }

    static func loaded(from url: URL = defaultURL) -> AppSettings {
        guard let data = try? Data(contentsOf: url) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Journal.log("settings.unreadable", ["reason": error.localizedDescription])
            return AppSettings()
        }
    }

    func save(to url: URL = AppSettings.defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func isAUsablePort(_ port: Int) -> Bool {
        (1024...65535).contains(port)
    }

    static func isAUsableSettle(_ seconds: Int) -> Bool {
        (0...600).contains(seconds)
    }

    static func isBelowTheDefaultSettle(_ seconds: Int) -> Bool {
        seconds < Int(GatewayRefusal.defaultSettle)
    }
}
