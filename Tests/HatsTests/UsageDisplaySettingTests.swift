import XCTest
@testable import Hats

final class UsageDisplaySettingTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hats-usage-display-\(UUID().uuidString)/settings.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        super.tearDown()
    }

    private func write(_ json: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    func testTheDefaultIsPercent() {
        XCTAssertEqual(AppSettings().usageDisplay, .percent)
        XCTAssertEqual(AppSettings.loaded(from: url).usageDisplay, .percent)
    }

    func testBarsSurvivesASaveAndALoad() throws {
        var settings = AppSettings()
        settings.usageDisplay = .bars
        try settings.save(to: url)
        XCTAssertEqual(AppSettings.loaded(from: url).usageDisplay, .bars)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains(#""usageDisplay" : "bars""#))
    }

    func testAMissingOrBrokenValueIsPercentAndKeepsEveryOtherSetting() throws {
        let others = #""gatewayPort": 9001, "autoSwitch": {"isOn": true, "sessionThresholdPercent": 50, "#
            + #""weeklyThresholdPercent": null, "order": ["b", "a"], "notifies": false}, "#
            + #""contextThresholds": {"warnPercent": 40, "savePercent": 50}, "#
            + #""limitThresholds": {"warnPercent": 20, "savePercent": 30}"#
        let reference = try decoded("{\(others)}")
        XCTAssertEqual(reference.gatewayPort, 9001)
        XCTAssertTrue(reference.autoSwitch.isOn)
        XCTAssertEqual(reference.autoSwitch.sessionThresholdPercent, 50)
        XCTAssertNotEqual(reference.contextThresholds, ContextThresholds())
        XCTAssertNotEqual(reference.limitThresholds, LimitThresholds())

        for broken in [#""graph""#, "5", "[]", "{}", "null"] {
            let settings = try decoded("{\(others), \"usageDisplay\": \(broken)}")
            XCTAssertEqual(settings.usageDisplay, .percent, broken)
            XCTAssertEqual(settings, reference, broken)
        }
    }

    private func decoded(_ json: String) throws -> AppSettings {
        try write(json)
        return AppSettings.loaded(from: url)
    }
}
