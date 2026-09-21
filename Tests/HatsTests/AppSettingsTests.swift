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
        settings.announcedUpdate = "0.2.0"
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

    func testAFileWrittenBeforeTheBlindSwitchKeepsEverySettingItCarried() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let written = """
        {
          "autoSwitch" : {
            "isOn" : true,
            "notifies" : false,
            "order" : ["b", "a"],
            "sessionThresholdPercent" : 80,
            "weeklyThresholdPercent" : 93
          },
          "autoSwitchRecord" : {
            "firedAt" : 780000000,
            "from" : "b",
            "limit" : "session",
            "seenInPopover" : true,
            "to" : "a"
          },
          "blinksTheCursorInTheMenuBar" : false,
          "gatewayPort" : 9123,
          "gatewaySettleSeconds" : 42,
          "isGatewayEnabled" : false,
          "showsHatNameInTheMenuBar" : false
        }
        """
        try Data(written.utf8).write(to: url)
        let settings = AppSettings.loaded(from: url)

        XCTAssertEqual(settings.gatewayPort, 9123,
                       "AppSettings.loaded answers with the whole defaults on any decoding error, "
                           + "so one required key added inside the nested record would silently "
                           + "take the gateway port, the thresholds and the hat order with it")
        XCTAssertEqual(settings.gatewaySettleSeconds, 42)
        XCTAssertFalse(settings.isGatewayEnabled)
        XCTAssertFalse(settings.showsHatNameInTheMenuBar)
        XCTAssertFalse(settings.blinksTheCursorInTheMenuBar)
        XCTAssertEqual(settings.autoSwitch.order, ["b", "a"])
        XCTAssertEqual(settings.autoSwitch.sessionThresholdPercent, 80)
        XCTAssertEqual(settings.autoSwitch.weeklyThresholdPercent, 93)
        XCTAssertTrue(settings.autoSwitch.isOn)
        XCTAssertFalse(settings.autoSwitch.notifies)
        XCTAssertEqual(settings.autoSwitchRecord?.from, "b")
        XCTAssertEqual(settings.autoSwitchRecord?.limit, .session)
        XCTAssertNil(settings.autoSwitchRecord?.cause,
                     "the file predates the field, and an Optional is the only kind of new field "
                         + "that decodes from a file which never carried it")
        XCTAssertTrue(settings.autoSwitchRecord?.seenInPopover ?? false)
    }

    private struct RecordAsAnOlderBuildReadsIt: Codable {
        let firedAt: Date
        let from: String
        let to: String
        let limit: UsageLimit
        let resetsAt: Date?
        var seenInPopover = false
    }

    private struct SettingsAsAnOlderBuildReadsIt: Codable {
        let gatewayPort: Int
        let autoSwitchRecord: RecordAsAnOlderBuildReadsIt?
    }

    func testARecordWrittenByABlindSwitchStillReadsOnTheBuildBeforeIt() throws {
        var settings = AppSettings()
        settings.gatewayPort = 9123
        settings.autoSwitchRecord = AutoSwitchRecord(
            firedAt: Date(timeIntervalSince1970: 1_800_000_000),
            from: "b",
            to: "a",
            limit: .weekly,
            resetsAt: nil,
            cause: .usageCouldNotBeRead
        )
        try settings.save(to: url)

        let older = try JSONDecoder().decode(SettingsAsAnOlderBuildReadsIt.self,
                                             from: Data(contentsOf: url))
        XCTAssertEqual(older.autoSwitchRecord?.limit, .weekly,
                       "0.2.2 declares limit as a plain UsageLimit, so a record without the key "
                           + "throws keyNotFound - and AppSettings.loaded answers any decoding "
                           + "error with the whole defaults, which would cost a person who rolled "
                           + "back their gateway port, their thresholds and their hat order")
        XCTAssertEqual(older.gatewayPort, 9123)
        XCTAssertEqual(AppSettings.loaded(from: url), settings,
                       "and the build that wrote it still reads its own file unchanged")
        XCTAssertEqual(settings.autoSwitchRecord?.journalReason, "usageCouldNotBeRead",
                       "the limit is there for the older build to parse, not to be reported as a "
                           + "threshold that was crossed")
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
