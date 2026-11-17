import XCTest
@testable import Hats

final class ContextThresholdsTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hats-context-\(UUID().uuidString)/settings.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        super.tearDown()
    }

    private func load(_ json: String) throws -> AppSettings {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)

        return AppSettings.loaded(from: url)
    }

    private func thresholds(_ warn: Int?, _ save: Int?, _ after: AfterSave = .offerClear) -> ContextThresholds {
        var made = ContextThresholds()
        made.warnPercent = warn
        made.savePercent = save
        made.afterSave = after

        return made
    }

    func testWithoutTheFieldTheThresholdsAre60And70AndTheActionOffersClear() throws {
        let defaults = thresholds(60, 70, .offerClear)

        XCTAssertEqual(AppSettings.loaded(from: url).contextThresholds, defaults, "no settings file at all")
        XCTAssertEqual(try load("{}").contextThresholds, defaults, "a settings file from before this version")
        XCTAssertEqual(try load(#"{"contextThresholds": {}}"#).contextThresholds, defaults)
        XCTAssertEqual(try load(#"{"contextThresholds": null}"#).contextThresholds, defaults)
        XCTAssertEqual(ContextThresholds(), defaults)
    }

    func testChangedValuesAndAThresholdTurnedOffSurviveARestartWithAnExplicitNull() throws {
        let cases: [(String, ContextThresholds)] = [
            ("only warn", thresholds(30, nil, .tell)),
            ("only anchor", thresholds(nil, 70, .offerExit)),
            ("both off", thresholds(nil, nil, .offerClear)),
            ("both on, moved", thresholds(20, 21, .tell)),
            ("clear and go on", thresholds(45, 55, .clear)),
        ]
        for (name, chosen) in cases {
            var settings = AppSettings()
            settings.contextThresholds = chosen
            try settings.save(to: url)

            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(AppSettings.loaded(from: url).contextThresholds, chosen, name)
            XCTAssertEqual(
                text.contains(#""warnPercent" : null"#),
                chosen.warnPercent == nil,
                "\(name): an off threshold is written as null, or the next start reads the default back"
            )
            XCTAssertEqual(text.contains(#""savePercent" : null"#), chosen.savePercent == nil, name)
        }
    }

    func testAMissingThresholdTakesItsDefaultWhileANullOneIsOff() throws {
        XCTAssertEqual(try load(#"{"contextThresholds": {"warnPercent": null}}"#).contextThresholds, thresholds(nil, 70))
        XCTAssertEqual(try load(#"{"contextThresholds": {"savePercent": 80}}"#).contextThresholds, thresholds(60, 80))
        XCTAssertEqual(
            try load(#"{"contextThresholds": {"warnPercent": null, "savePercent": null, "afterSave": "tell"}}"#)
                .contextThresholds,
            thresholds(nil, nil, .tell)
        )
    }

    func testTheEdgesOfBothRangesAreKept() throws {
        XCTAssertEqual(
            try load(#"{"contextThresholds": {"warnPercent": 10, "savePercent": 11}}"#).contextThresholds,
            thresholds(10, 11)
        )
        XCTAssertEqual(
            try load(#"{"contextThresholds": {"warnPercent": 94, "savePercent": 95}}"#).contextThresholds,
            thresholds(94, 95)
        )
        XCTAssertEqual(try load(#"{"contextThresholds": {"warnPercent": 94, "savePercent": null}}"#).contextThresholds,
                       thresholds(94, nil))
        XCTAssertEqual(try load(#"{"contextThresholds": {"warnPercent": null, "savePercent": 11}}"#).contextThresholds,
                       thresholds(nil, 11))
    }

    func testUnusableThresholdsFallBackTogetherWhileTheActionIsJudgedApart() throws {
        let unusable = [
            #""warnPercent": 9"#,
            #""warnPercent": 95, "savePercent": null"#,
            #""savePercent": 10, "warnPercent": null"#,
            #""savePercent": 96"#,
            #""warnPercent": 60, "savePercent": 55"#,
            #""warnPercent": 55, "savePercent": 55"#,
            #""warnPercent": "45""#,
            #""warnPercent": 45.5"#,
            #""savePercent": true"#,
            #""savePercent": [55]"#,
        ]
        for pair in unusable {
            let settings = try load(#"{"contextThresholds": {\#(pair), "afterSave": "tell"}}"#)

            XCTAssertEqual(settings.contextThresholds, thresholds(60, 70, .tell),
                           "\(pair): both thresholds go back to 60 and 70, the action is kept")
        }
    }

    func testAnUnknownOrMistypedActionOffersClearAndKeepsTheThresholds() throws {
        for action in [#""clear_all""#, #""offer_new""#, "5", "null", #"{"tell": true}"#] {
            let settings = try load(#"{"contextThresholds": {"warnPercent": 30, "savePercent": 40, "afterSave": \#(action)}}"#)

            XCTAssertEqual(settings.contextThresholds, thresholds(30, 40, .offerClear), action)
        }
    }

    func testABadContextPartFallsBackByPartAndLeavesTheGatewayPortAndAutoSwitchAlone() throws {
        let parts: [(String, ContextThresholds)] = [
            (#"{"warnPercent": 30, "savePercent": 40, "afterSave": "clear_all"}"#, thresholds(30, 40, .offerClear)),
            (#"{"warnPercent": 30, "savePercent": 40, "afterSave": "clear"}"#, thresholds(30, 40, .clear)),
            (#"{"warnPercent": 60, "savePercent": 40, "afterSave": "tell"}"#, thresholds(60, 70, .tell)),
            (#""anchor at 55""#, thresholds(60, 70, .offerClear)),
            ("[45, 55]", thresholds(60, 70, .offerClear)),
        ]
        for (part, expected) in parts {
            let settings = try load("""
                {
                  "gatewayPort": 9001,
                  "autoSwitch": {"isOn": true, "notifies": false, "order": ["b", "a"],
                                 "sessionThresholdPercent": 80, "weeklyThresholdPercent": 93},
                  "contextThresholds": \(part)
                }
                """)

            XCTAssertEqual(settings.contextThresholds, expected, part)
            XCTAssertEqual(settings.gatewayPort, 9001, part)
            XCTAssertTrue(settings.autoSwitch.isOn, part)
            XCTAssertEqual(settings.autoSwitch.order, ["b", "a"], part)
            XCTAssertEqual(settings.autoSwitch.sessionThresholdPercent, 80, part)
            XCTAssertEqual(settings.autoSwitch.weeklyThresholdPercent, 93, part)
            XCTAssertFalse(settings.autoSwitch.notifies, part)
        }
    }

    func testTheContextTabShowsThePanelThatSavesThroughTheActions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let tabs = try String(contentsOf: root.appendingPathComponent("Sources/Hats/SettingsWindow.swift"), encoding: .utf8)
        let panel = try String(contentsOf: root.appendingPathComponent("Sources/Hats/ContextThresholdsPanel.swift"),
                               encoding: .utf8)

        XCTAssertTrue(tabs.contains("            ContextThresholdsPanel(model: model)\n"
                                        + "                .tabItem { Text(\"Context\") }"))
        let rows = [
            """
                        threshold(
                            HatsCopy.warnAt,
                            percent: thresholds.warnPercent,
                            range: thresholds.getWarnRange(),
                            toggle: { next, isOn in next.setWarn(isOn: isOn) },
                            step: { next, percent in next.setWarn(percent) }
                        )
                        drain
                        threshold(
                            HatsCopy.anchorAt,
                            percent: thresholds.savePercent,
                            range: thresholds.getSaveRange(),
                            toggle: { next, isOn in next.setSave(isOn: isOn) },
                            step: { next, percent in next.setSave(percent) }
                        )
                        afterAnchoring
                        Text(HatsCopy.contextThresholdsNote)
            """,
            """
                    HStack {
                        Toggle(label, isOn: Binding(
                            get: { percent != nil },
                            set: { isOn in change { toggle(&$0, isOn) } }
                        ))
                        .font(.system(size: 13))
                        Spacer()
                        if let percent {
                            Stepper(
                                "\\(percent)%",
                                value: Binding(
                                    get: { percent },
                                    set: { value in change { step(&$0, value) } }
                                ),
                                in: range,
                                step: 1
                            )
            """,
            """
                    Picker(HatsCopy.afterAnchoring, selection: Binding(
                        get: { thresholds.afterSave },
                        set: { action in change { $0.afterSave = action } }
                    )) {
                        ForEach(AfterSave.allCases, id: \\.self) { action in
                            Text(HatsCopy.getAfterSaveTitle(action)).tag(action)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .font(.system(size: 13))
                    .disabled(thresholds.savePercent == nil)
            """,
            """
                    var next = thresholds
                    body(&next)
                    model.actions?.updateContextThresholds(next)
            """,
            """
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle(HatsCopy.drainBackgroundWork, isOn: Binding(
                                get: { thresholds.drain },
                                set: { isOn in change { $0.drain = isOn } }
                            ))
                            .font(.system(size: 13))
                            Spacer()
                            if thresholds.drain {
                                Stepper(
                                    HatsCopy.getDrainWaitTitle(minutes: thresholds.drainMinutes),
                                    value: Binding(
                                        get: { thresholds.drainMinutes },
                                        set: { minutes in change { $0.setDrainMinutes(minutes) } }
                                    ),
                                    in: ContextThresholds.drainMinutesRange,
                                    step: 1
                                )
                                .font(.system(size: 13))
                            }
                        }
                        .disabled(thresholds.savePercent == nil)
                        Text(HatsCopy.drainNote)
            """,
        ]
        for row in rows {
            XCTAssertTrue(panel.contains(row), "the panel no longer reads, as one block:\n\(row)")
        }
    }

    func testWithoutTheDrainFieldsTheDrainIsOffAndWaitsTenMinutes() throws {
        let settings = try load(#"{"contextThresholds": {"warnPercent": 30, "savePercent": 40, "afterSave": "tell"}}"#)

        XCTAssertFalse(settings.contextThresholds.drain)
        XCTAssertEqual(settings.contextThresholds.drainMinutes, 10)
        XCTAssertEqual(settings.contextThresholds, thresholds(30, 40, .tell))
        XCTAssertFalse(ContextThresholds().drain)
        XCTAssertEqual(ContextThresholds().drainMinutes, 10)
    }

    func testTheDrainAndItsMinutesSurviveARestart() throws {
        var chosen = thresholds(45, 55, .clear)
        chosen.drain = true
        chosen.drainMinutes = 25
        var settings = AppSettings()
        settings.contextThresholds = chosen
        try settings.save(to: url)

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(AppSettings.loaded(from: url).contextThresholds, chosen)
        XCTAssertTrue(text.contains(#""drain" : true"#), text)
        XCTAssertTrue(text.contains(#""drainMinutes" : 25"#), text)
    }

    func testBadDrainFieldsFallBackOneByOneAndLeaveTheThresholdsAlone() throws {
        let cases: [(String, Bool, Int)] = [
            (#""drain": true, "drainMinutes": 0"#, true, 10),
            (#""drain": true, "drainMinutes": 61"#, true, 10),
            (#""drain": true, "drainMinutes": 5.5"#, true, 10),
            (#""drain": true, "drainMinutes": "5""#, true, 10),
            (#""drain": "true", "drainMinutes": 1"#, false, 1),
            (#""drain": 1, "drainMinutes": 60"#, false, 60),
            (#""drain": null, "drainMinutes": null"#, false, 10),
        ]
        for (fields, drain, minutes) in cases {
            let part = #"{"warnPercent": 30, "savePercent": 40, "afterSave": "tell", \#(fields)}"#
            let settings = try load(#"{"contextThresholds": \#(part)}"#)

            XCTAssertEqual(settings.contextThresholds.drain, drain, fields)
            XCTAssertEqual(settings.contextThresholds.drainMinutes, minutes, fields)
            XCTAssertEqual(settings.contextThresholds.warnPercent, 30, fields)
            XCTAssertEqual(settings.contextThresholds.savePercent, 40, fields)
            XCTAssertEqual(settings.contextThresholds.afterSave, .tell, fields)
        }
    }

    func testTheWaitStaysFromOneToSixtyMinutes() {
        var chosen = ContextThresholds()

        chosen.setDrainMinutes(0)
        XCTAssertEqual(chosen.drainMinutes, 1)
        chosen.setDrainMinutes(61)
        XCTAssertEqual(chosen.drainMinutes, 60)
        chosen.setDrainMinutes(7)
        XCTAssertEqual(chosen.drainMinutes, 7)
        XCTAssertEqual(ContextThresholds.drainMinutesRange, 1...60)
    }

    func testTheSteppersKeepWarnBelowAnchor() {
        XCTAssertEqual(thresholds(45, 55).getWarnRange(), 10...54)
        XCTAssertEqual(thresholds(45, 55).getSaveRange(), 46...95)
        XCTAssertEqual(thresholds(45, nil).getWarnRange(), 10...94, "anchor off: warn may go to the top of its own range")
        XCTAssertEqual(thresholds(nil, 55).getSaveRange(), 11...95, "warn off: anchor may go to the bottom of its own range")
        XCTAssertEqual(thresholds(10, 11).getWarnRange(), 10...10)
        XCTAssertEqual(thresholds(10, 11).getSaveRange(), 11...95)
        XCTAssertEqual(thresholds(94, 95).getSaveRange(), 95...95)

        var moved = thresholds(45, 55)
        moved.setWarn(70)
        XCTAssertEqual(moved.warnPercent, 54, "warn stops one below anchor")
        moved.setSave(20)
        XCTAssertEqual(moved.savePercent, 55, "anchor stops one above warn")
        moved.setWarn(3)
        XCTAssertEqual(moved.warnPercent, 10)
        moved.setSave(200)
        XCTAssertEqual(moved.savePercent, 95)

        var off = thresholds(nil, 55)
        off.setWarn(30)
        XCTAssertNil(off.warnPercent, "a step on an off threshold does not turn it on")
    }

    func testTheTogglesWriteNullAndComeBackAt60And70OrNextToTheOther() {
        var chosen = thresholds(60, 70)
        chosen.setWarn(isOn: false)
        XCTAssertEqual(chosen, thresholds(nil, 70))
        chosen.setSave(isOn: false)
        XCTAssertEqual(chosen, thresholds(nil, nil))
        chosen.setWarn(isOn: true)
        chosen.setSave(isOn: true)
        XCTAssertEqual(chosen, thresholds(60, 70))

        var low = thresholds(nil, 11)
        low.setWarn(isOn: true)
        XCTAssertEqual(low.warnPercent, 10, "anchor at 11: warn comes back at 10, not above it")

        var high = thresholds(94, nil)
        high.setSave(isOn: true)
        XCTAssertEqual(high.savePercent, 95, "warn at 94: anchor comes back at 95, not below it")

        var near = thresholds(nil, 30)
        near.setWarn(isOn: true)
        XCTAssertEqual(near.warnPercent, 29)

        var above = thresholds(80, nil)
        above.setSave(isOn: true)
        XCTAssertEqual(above.savePercent, 81)

        var roomy = thresholds(20, nil)
        roomy.setSave(isOn: true)
        XCTAssertEqual(roomy.savePercent, 70, "with room, the default comes back")
    }
}
