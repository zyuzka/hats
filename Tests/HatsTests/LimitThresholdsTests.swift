import XCTest
@testable import Hats

final class LimitThresholdsTests: XCTestCase {
    private var url: URL!
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hats-limits-\(UUID().uuidString)")
        url = root.appendingPathComponent("settings.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func load(_ json: String) throws -> AppSettings {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)

        return AppSettings.loaded(from: url)
    }

    private func limits(_ warn: Int?, _ save: Int?) -> LimitThresholds {
        var made = LimitThresholds()
        made.warnPercent = warn
        made.savePercent = save

        return made
    }

    private func source(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(name)

        return try String(contentsOf: url, encoding: .utf8)
    }

    func testWithoutTheFieldTheLimitThresholdsAre70And80() throws {
        XCTAssertEqual(LimitThresholds().warnPercent, 70)
        XCTAssertEqual(LimitThresholds().savePercent, 80)
        XCTAssertEqual(AppSettings.loaded(from: url).limitThresholds, limits(70, 80), "no settings file at all")
        XCTAssertEqual(try load("{}").limitThresholds, limits(70, 80), "a settings file from before this version")
        XCTAssertEqual(try load(#"{"limitThresholds": {}}"#).limitThresholds, limits(70, 80))
        XCTAssertEqual(try load(#"{"limitThresholds": null}"#).limitThresholds, limits(70, 80))
    }

    func testAMissingThresholdTakesItsDefaultWhileANullOneIsOff() throws {
        XCTAssertEqual(try load(#"{"limitThresholds": {"warnPercent": null}}"#).limitThresholds, limits(nil, 80))
        XCTAssertEqual(try load(#"{"limitThresholds": {"savePercent": null}}"#).limitThresholds, limits(70, nil))
        XCTAssertEqual(try load(#"{"limitThresholds": {"savePercent": 90}}"#).limitThresholds, limits(70, 90))
        XCTAssertEqual(try load(#"{"limitThresholds": {"warnPercent": 20}}"#).limitThresholds, limits(20, 80))
    }

    func testTheEdgesOfTheRangeAreKept() throws {
        let kept: [(String, LimitThresholds)] = [
            (#"{"warnPercent": 10, "savePercent": 11}"#, limits(10, 11)),
            (#"{"warnPercent": 94, "savePercent": 95}"#, limits(94, 95)),
            (#"{"warnPercent": 95, "savePercent": null}"#, limits(95, nil)),
            (#"{"warnPercent": null, "savePercent": 10}"#, limits(nil, 10)),
        ]
        for (part, expected) in kept {
            XCTAssertEqual(try load(#"{"limitThresholds": \#(part)}"#).limitThresholds, expected, part)
        }
    }

    func testABrokenPairFallsBackTo70And80AndLeavesTheOtherSettingsAlone() throws {
        let broken = [
            #""warnPercent": 9"#,
            #""savePercent": 96"#,
            #""warnPercent": 96, "savePercent": null"#,
            #""warnPercent": 80, "savePercent": 80"#,
            #""warnPercent": 85, "savePercent": 80"#,
            #""warnPercent": 70.5"#,
            #""savePercent": "80""#,
            #""warnPercent": true"#,
        ]
        for pair in broken {
            let settings = try load("""
                {
                  "gatewayPort": 9001,
                  "autoSwitch": {"isOn": true, "notifies": false, "order": ["b", "a"],
                                 "sessionThresholdPercent": 85, "weeklyThresholdPercent": 93},
                  "contextThresholds": {"warnPercent": 30, "savePercent": 40, "afterSave": "tell"},
                  "limitThresholds": {\(pair)}
                }
                """)

            XCTAssertEqual(settings.limitThresholds, limits(70, 80), pair)
            XCTAssertEqual(settings.gatewayPort, 9001, pair)
            XCTAssertTrue(settings.autoSwitch.isOn, pair)
            XCTAssertEqual(settings.autoSwitch.sessionThresholdPercent, 85, pair)
            XCTAssertEqual(settings.contextThresholds.warnPercent, 30, pair)
            XCTAssertEqual(settings.contextThresholds.savePercent, 40, pair)
        }
        for part in [#""warn at 70""#, "[70, 80]"] {
            let settings = try load(#"{"gatewayPort": 9001, "limitThresholds": \#(part)}"#)
            XCTAssertEqual(settings.limitThresholds, limits(70, 80), part)
            XCTAssertEqual(settings.gatewayPort, 9001, part)
        }
    }

    func testAThresholdTurnedOffSurvivesARestartAsAnExplicitNull() throws {
        for chosen in [limits(nil, 80), limits(70, nil), limits(nil, nil), limits(30, 31)] {
            var settings = AppSettings()
            settings.limitThresholds = chosen
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try settings.save(to: url)

            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(AppSettings.loaded(from: url).limitThresholds, chosen, "\(chosen)")
            let part = try XCTUnwrap(text.range(of: #""limitThresholds" : {"#)).upperBound
            let block = text[part...].prefix { $0 != "}" }
            XCTAssertEqual(block.contains(#""warnPercent" : null"#), chosen.warnPercent == nil, "\(chosen): \(block)")
            XCTAssertEqual(block.contains(#""savePercent" : null"#), chosen.savePercent == nil, "\(chosen): \(block)")
        }
    }

    func testTheSteppersKeepWarnBelowAnchorInsideTenToNinetyFive() {
        XCTAssertEqual(limits(70, 80).getWarnRange(), 10...79)
        XCTAssertEqual(limits(70, 80).getSaveRange(), 71...95)
        XCTAssertEqual(limits(70, nil).getWarnRange(), 10...95)
        XCTAssertEqual(limits(nil, 80).getSaveRange(), 10...95)

        var moved = limits(70, 80)
        moved.setWarn(90)
        XCTAssertEqual(moved.warnPercent, 79, "warn stops one below anchor")
        moved.setSave(20)
        XCTAssertEqual(moved.savePercent, 80, "anchor stops one above warn")
        moved.setWarn(1)
        XCTAssertEqual(moved.warnPercent, 10)
        moved.setSave(200)
        XCTAssertEqual(moved.savePercent, 95)

        var off = limits(nil, 80)
        off.setWarn(30)
        XCTAssertNil(off.warnPercent, "a step on an off threshold does not turn it on")
    }

    func testTheTogglesWriteNullAndComeBackAt70And80OrNextToTheOther() {
        var chosen = limits(70, 80)
        chosen.setWarn(isOn: false)
        XCTAssertEqual(chosen, limits(nil, 80))
        chosen.setSave(isOn: false)
        XCTAssertEqual(chosen, limits(nil, nil))
        chosen.setWarn(isOn: true)
        chosen.setSave(isOn: true)
        XCTAssertEqual(chosen, limits(70, 80))

        var low = limits(nil, 40)
        low.setWarn(isOn: true)
        XCTAssertEqual(low.warnPercent, 39)

        var high = limits(90, nil)
        high.setSave(isOn: true)
        XCTAssertEqual(high.savePercent, 91)

        var none = limits(nil, 10)
        none.setWarn(isOn: true)
        XCTAssertNil(none.warnPercent, "anchor at 10 leaves no room below it, so warn stays off")

        var top = limits(95, nil)
        top.setSave(isOn: true)
        XCTAssertNil(top.savePercent, "warn at 95 leaves no room above it, so anchor stays off")
    }

    func testTheThresholdsFileCarriesTheLimitThresholdsAndAnOffOneAsNull() throws {
        var file = WindowThresholdsFile(root: root)
        let cases: [(LimitThresholds, Any, Any)] = [
            (limits(70, 80), 70, 80),
            (limits(nil, 80), NSNull(), 80),
            (limits(70, nil), 70, NSNull()),
        ]
        for (chosen, warn, save) in cases {
            XCTAssertEqual(file.setThresholds(ContextThresholds(), limits: chosen, at: now), .written, "\(chosen)")

            let data = try Data(contentsOf: file.url)
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(fields["limit_warn_percent"] as? NSObject, warn as? NSObject, "\(chosen)")
            XCTAssertEqual(fields["limit_save_percent"] as? NSObject, save as? NSObject, "\(chosen)")
            XCTAssertEqual(fields["warn_percent"] as? Int, 60, "the window thresholds stay beside them")
        }
        XCTAssertEqual(file.setThresholds(ContextThresholds(), limits: limits(70, nil), at: now), .unchanged)
    }

    func testAChangeOfTheLimitThresholdsAloneRewritesTheFile() throws {
        var file = WindowThresholdsFile(root: root)
        XCTAssertEqual(file.setThresholds(ContextThresholds(), limits: limits(70, 80), at: now), .written)

        XCTAssertEqual(file.setThresholds(ContextThresholds(), limits: limits(60, 80), at: now), .written)

        let data = try Data(contentsOf: file.url)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(fields["limit_warn_percent"] as? Int, 60)
    }

    func testEveryRedrawWritesTheLimitThresholdsAndAChangeIsSavedAndRedrawn() throws {
        let redraw = try source("Sources/Hats/AppDelegate+Redraw.swift")
        let update = try source("Sources/Hats/AppDelegate+ContextThresholds.swift")

        XCTAssertTrue(redraw.contains(
            "contextChannel.setThresholds(settings.contextThresholds, limits: settings.limitThresholds, at: Date())"
        ))
        XCTAssertTrue(update.contains("settings.limitThresholds = thresholds\n        saveSettings()\n        redraw()"))
    }

    func testTheContextTabHasAHatLimitSectionWithAToggleAndStepperPerThreshold() throws {
        let panel = try source("Sources/Hats/ContextThresholdsPanel.swift")
        let section = try source("Sources/Hats/HatLimitSection.swift")
        let rows = [
            """
                        Text(HatsCopy.hatLimit)
                            .font(.system(size: 13, weight: .semibold))
                        limitThreshold(
                            HatsCopy.warnAt,
                            percent: limits.warnPercent,
                            range: limits.getWarnRange(),
                            toggle: { next, isOn in next.setWarn(isOn: isOn) },
                            step: { next, percent in next.setWarn(percent) }
                        )
                        limitThreshold(
                            HatsCopy.anchorAt,
                            percent: limits.savePercent,
                            range: limits.getSaveRange(),
                            toggle: { next, isOn in next.setSave(isOn: isOn) },
                            step: { next, percent in next.setSave(percent) }
                        )
                        Text(HatsCopy.limitThresholdsNote)
            """,
            """
                    var next = limits
                    body(&next)
                    model.actions?.updateLimitThresholds(next)
            """,
            """
                        Toggle(label, isOn: Binding(
                            get: { percent != nil },
                            set: { isOn in changeLimits { toggle(&$0, isOn) } }
                        ))
            """,
            """
                                set: { value in changeLimits { step(&$0, value) } }
            """,
            """
                        Text(HatsCopy.contextThresholdsNote)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HatLimitSection(model: model)
            """,
        ]
        for row in rows {
            XCTAssertTrue((panel + section).contains(row), "the panel no longer reads, as one block:\n\(row)")
        }
    }

    func testTheTextsOfTheHatLimitSection() {
        XCTAssertEqual(HatsCopy.hatLimit, "Hat limit")
        XCTAssertEqual(
            HatsCopy.limitThresholdsNote,
            "Acts when Hats will not switch the worn hat away from that limit: no other hat is free, auto-switch is "
                + "off, or its switch threshold is off. Sessions on the worn hat are told, and anchor at the end of a turn."
        )
    }
}
