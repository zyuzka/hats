import XCTest
@testable import Hats

final class AppSettingsTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hats-settings-\(UUID().uuidString)/settings.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        super.tearDown()
    }

    func testAMissingFileIsTheDefaults() {
        let settings = AppSettings.loaded(from: url)
        XCTAssertEqual(settings, AppSettings())
        XCTAssertEqual(settings.gatewayPort, 8787)
        XCTAssertTrue(settings.isGatewayEnabled)
        XCTAssertFalse(settings.autoSwitch.isOn, "auto-switch is a choice, off until made")
    }

    func testSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.gatewayPort = 8788
        settings.isGatewayEnabled = false
        settings.autoSwitch.isOn = true
        settings.autoSwitch.order = ["b", "a"]
        settings.foreignProfileResolution = .keepMine
        try settings.save(to: url)
        XCTAssertEqual(AppSettings.loaded(from: url), settings)
    }

    func testAFileFromAnOlderVersionFillsInWhatItLacks() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(#"{"gatewayPort": 9000}"#.utf8).write(to: url)
        let settings = AppSettings.loaded(from: url)
        XCTAssertEqual(settings.gatewayPort, 9000)
        XCTAssertTrue(settings.isGatewayEnabled, "a key the old version never wrote takes the default")
        XCTAssertEqual(settings.autoSwitch, AutoSwitchPolicy())
    }

    func testACorruptFileIsTheDefaultsRatherThanACrash() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        XCTAssertEqual(AppSettings.loaded(from: url), AppSettings())
    }

    func testAnUnusablePortInTheFileFallsBackToTheDefault() throws {
        for raw in ["0", "-5", "80", "70000"] {
            let data = Data(#"{"gatewayPort": "#.utf8) + Data(raw.utf8) + Data("}".utf8)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            XCTAssertEqual(settings.gatewayPort, 8787, "a port the panel would refuse is not taken from the file either: \(raw)")
        }
        let fine = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"gatewayPort": 9000}"#.utf8))
        XCTAssertEqual(fine.gatewayPort, 9000)
    }

    func testOnlyUnprivilegedPortsAreUsable() {
        XCTAssertFalse(AppSettings.isAUsablePort(80), "binding below 1024 needs root")
        XCTAssertFalse(AppSettings.isAUsablePort(1023))
        XCTAssertTrue(AppSettings.isAUsablePort(1024))
        XCTAssertTrue(AppSettings.isAUsablePort(8787))
        XCTAssertTrue(AppSettings.isAUsablePort(65535))
        XCTAssertFalse(AppSettings.isAUsablePort(65536))
        XCTAssertFalse(AppSettings.isAUsablePort(0))
    }
}
