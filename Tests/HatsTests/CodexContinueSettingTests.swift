import XCTest
@testable import Hats

final class CodexContinueSettingTests: XCTestCase {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testTheSwitchIsOnByDefault() {
        XCTAssertTrue(AppSettings().continuesCodexAfterCompaction)
    }

    func testAFileFromBeforeTheSwitchReadsAsOnAndKeepsTheRest() throws {
        let old = try decode(#"{"gatewayPort": 9001, "contextThresholds": {"warnPercent": 40, "savePercent": 50}}"#)
        XCTAssertTrue(old.continuesCodexAfterCompaction)
        XCTAssertEqual(old.gatewayPort, 9001)
        XCTAssertEqual(old.contextThresholds.savePercent, 50)
    }

    func testOffSurvivesAnEncodeAndADecode() throws {
        var settings = AppSettings()
        settings.continuesCodexAfterCompaction = false
        let data = try JSONEncoder().encode(settings)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: data).continuesCodexAfterCompaction)
    }

    func testABrokenValueReadsAsOn() throws {
        XCTAssertTrue(try decode(#"{"continuesCodexAfterCompaction": "no"}"#).continuesCodexAfterCompaction)
    }
}
