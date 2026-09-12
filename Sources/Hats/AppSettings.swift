import Foundation

enum ForeignProfileResolution: String, Codable, Equatable {
    case undecided
    case keepMine
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
    var announcedUpdate: String?

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
        announcedUpdate = try c.decodeIfPresent(String.self, forKey: .announcedUpdate)
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
