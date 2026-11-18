import XCTest
@testable import Hats

final class SettingsDraftsTests: XCTestCase {
    private func settings(warn: Int? = 60, save: Int? = 70) -> AppSettings {
        var made = AppSettings()
        made.contextThresholds.warnPercent = warn
        made.contextThresholds.savePercent = save
        made.autoSwitch.sessionThresholdPercent = 90
        made.gatewaySettleSeconds = 35

        return made
    }

    func testDraftsOnTwoTabsAreAppliedTogether() throws {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("65", of: .contextSave, in: stored)
        drafts.setText("20", of: .settle, in: stored)

        // Act
        let changes = try XCTUnwrap(drafts.getChanges(in: stored))

        // Assert
        XCTAssertTrue(drafts.canApply(in: stored))
        XCTAssertEqual(changes.contextThresholds?.savePercent, 65)
        XCTAssertEqual(changes.contextThresholds?.warnPercent, 60)
        XCTAssertEqual(changes.gatewaySettleSeconds, 20)
        XCTAssertNil(changes.autoSwitch)
        XCTAssertNil(changes.gatewayPort)
    }

    func testOneRefusedDraftBlocksApplyAndNamesItsReason() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("55", of: .contextSave, in: stored)
        drafts.setText("80", of: .sessionSwitch, in: stored)

        // Act
        let state = drafts.getState(.contextSave, in: stored)

        // Assert
        XCTAssertFalse(drafts.canApply(in: stored))
        XCTAssertNil(drafts.getChanges(in: stored))
        XCTAssertEqual(state.reason, "above Warn at 60%")
        XCTAssertTrue(state.isRefusedDraft)
        XCTAssertEqual(drafts.getState(.sessionSwitch, in: stored).applicable, 80)
    }

    func testThePairIsCheckedAgainstTheOtherDraft() throws {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("75", of: .contextWarn, in: stored)
        drafts.setText("85", of: .contextSave, in: stored)

        // Act
        let changes = try XCTUnwrap(drafts.getChanges(in: stored))

        // Assert
        XCTAssertEqual(changes.contextThresholds?.warnPercent, 75)
        XCTAssertEqual(changes.contextThresholds?.savePercent, 85)
        XCTAssertNil(drafts.getState(.contextWarn, in: stored).reason, "75 is below the drafted 85, not the stored 70")
    }

    func testCrossedDraftsAreBothRefused() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("80", of: .contextWarn, in: stored)
        drafts.setText("75", of: .contextSave, in: stored)

        // Act
        let canApply = drafts.canApply(in: stored)

        // Assert
        XCTAssertFalse(canApply)
        XCTAssertEqual(drafts.getState(.contextWarn, in: stored).reason, "below Anchor at 75%")
        XCTAssertEqual(drafts.getState(.contextSave, in: stored).reason, "above Warn at 80%")
    }

    func testANeighbourDraftOutsideItsOwnRangeLeavesTheStoredNeighbour() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("5", of: .contextSave, in: stored)

        // Act
        let bounds = drafts.getBounds(.contextWarn, in: stored)

        // Assert
        XCTAssertEqual(bounds.getStepRange(), 10...69)
        XCTAssertEqual(drafts.getState(.contextSave, in: stored).reason, "above Warn at 60%")
    }

    func testNoDraftsMeansNothingToApply() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("70", of: .contextSave, in: stored)
        drafts.setText("060", of: .contextWarn, in: stored)

        // Act
        let canApply = drafts.canApply(in: stored)

        // Assert
        XCTAssertFalse(canApply)
        XCTAssertFalse(drafts.hasPending(in: stored))
        XCTAssertNil(drafts.drafts[.contextSave], "text equal to the stored value is no draft")
    }

    func testOnlyDigitsReachTheField() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()

        // Act
        drafts.setText("6a5%", of: .contextSave, in: stored)

        // Assert
        XCTAssertEqual(drafts.getText(.contextSave, in: stored), "65")
        XCTAssertEqual(TypedNumber.getDigits("6a5%"), "65")
        XCTAssertEqual(TypedNumber.getDigits(" -1٣2.0 "), "120", "a sign, a dot and a non-Latin digit are dropped")
        XCTAssertEqual(TypedNumber.getDigitEdit("6a5%", cursor: 4).text, "65")
        XCTAssertEqual(TypedNumber.getDigitEdit("6a5%", cursor: 4).cursor, 2)
        XCTAssertEqual(TypedNumber.getDigitEdit("6a|5", cursor: 2).cursor, 1, "the cursor keeps its place among digits")
    }

    func testResetBringsBackTheStoredValue() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("65", of: .contextSave, in: stored)

        // Act
        drafts.reset(.contextSave)

        // Assert
        XCTAssertEqual(drafts.getText(.contextSave, in: stored), "70")
        XCTAssertNil(drafts.drafts[.contextSave])
    }

    func testADraftOutlivesAChangeOfItsNeighbourButNotOfItsOwnValue() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("65", of: .contextSave, in: stored)
        var stepped = stored
        stepped.contextThresholds.warnPercent = 61
        var ownStepped = stored
        ownStepped.contextThresholds.savePercent = 71

        // Act
        let afterNeighbour = drafts.getText(.contextSave, in: stepped)
        let afterOwn = drafts.getText(.contextSave, in: ownStepped)

        // Assert
        XCTAssertEqual(afterNeighbour, "65")
        XCTAssertEqual(afterOwn, "71", "the arrows wrote a new value, and the draft over the old one is gone")
    }

    func testTheCloseQuestionOffersApplyOnlyWhenEveryDraftIsUsable() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("700", of: .settle, in: stored)
        drafts.setText("20", of: .contextWarn, in: stored)

        // Act
        let answers = SettingsCloseQuestion.getAnswers(canApply: drafts.canApply(in: stored))

        // Assert
        XCTAssertTrue(drafts.hasPending(in: stored))
        XCTAssertEqual(answers, [.discard, .cancel])
        XCTAssertEqual(SettingsCloseQuestion.getAnswers(canApply: true), [.apply, .discard, .cancel])
        XCTAssertEqual(SettingsCloseQuestion.getAnswer(at: 0, among: answers), .discard)
        XCTAssertEqual(SettingsCloseQuestion.getAnswer(at: 1, among: answers), .cancel)
        XCTAssertEqual(SettingsCloseQuestion.getAnswer(at: 2, among: answers), .cancel, "out of range is cancel")
        XCTAssertEqual(SettingsCloseQuestion.getAnswer(at: -1, among: answers), .cancel)
    }

    func testAnUntouchedFieldIsJudgedAgainstTheStoredNeighbour() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("55", of: .contextSave, in: stored)

        // Act
        let warn = drafts.getState(.contextWarn, in: stored)

        // Assert
        XCTAssertNil(warn.reason, "one typed number gives one reason")
        XCTAssertEqual(drafts.getState(.contextSave, in: stored).reason, "above Warn at 60%")
    }

    func testAMovedStoredValueRemovesItsDraftForGood() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("65", of: .contextSave, in: stored)
        drafts.setText("50", of: .contextWarn, in: stored)
        var stepped = stored
        stepped.contextThresholds.savePercent = 71

        // Act
        drafts.prune(in: stepped)

        // Assert
        XCTAssertNil(drafts.drafts[.contextSave])
        XCTAssertEqual(drafts.getText(.contextSave, in: stored), "70", "arrowing back to 70 does not bring 65 back")
        XCTAssertEqual(drafts.drafts[.contextWarn]?.text, "50", "a neighbour's draft stays")
    }

    func testApplySendsEachValueToItsActionSettleBeforePort() {
        // Arrange
        let model = HatsModel()
        model.snapshot.settings = settings()
        let actions = RecordingActions(model: model, isPortMoved: true)
        model.actions = actions
        let drafts = SettingsDrafts()
        let stored = model.snapshot.settings
        drafts.setText("9000", of: .port, in: stored)
        drafts.setText("20", of: .settle, in: stored)
        drafts.setText("85", of: .weeklySwitch, in: stored)
        drafts.setText("65", of: .contextSave, in: stored)
        drafts.setText("75", of: .limitWarn, in: stored)

        // Act
        drafts.apply(model)

        // Assert
        XCTAssertEqual(actions.calls, [
            "settle 20",
            "port 9000",
            "autoSwitch 90 85",
            "context 60 65",
            "limits 75 80",
        ])
        XCTAssertEqual(drafts.drafts, [:])
        XCTAssertFalse(drafts.canApply(in: model.snapshot.settings))
    }

    func testARefusedPortMoveKeepsOnlyThePortDraft() {
        // Arrange
        let model = HatsModel()
        model.snapshot.settings = settings()
        let actions = RecordingActions(model: model, isPortMoved: false)
        model.actions = actions
        let drafts = SettingsDrafts()
        let stored = model.snapshot.settings
        drafts.setText("9000", of: .port, in: stored)
        drafts.setText("20", of: .settle, in: stored)

        // Act
        drafts.apply(model)

        // Assert
        XCTAssertEqual(Array(drafts.drafts.keys), [.port])
        XCTAssertEqual(drafts.getText(.port, in: model.snapshot.settings), "9000")
        XCTAssertTrue(drafts.hasPending(in: model.snapshot.settings), "the window stays open over the refusal")
    }

    func testTheLimitPairIsAppliedTogether() throws {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("85", of: .limitWarn, in: stored)
        drafts.setText("90", of: .limitSave, in: stored)

        // Act
        let changes = try XCTUnwrap(drafts.getChanges(in: stored))

        // Assert
        XCTAssertEqual(changes.limitThresholds?.warnPercent, 85)
        XCTAssertEqual(changes.limitThresholds?.savePercent, 90)
        XCTAssertNil(changes.contextThresholds)
    }

    func testTheWeeklyAutoSwitchFieldIsAppliedAndRefused() throws {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("85", of: .weeklySwitch, in: stored)
        let refused = SettingsDrafts()
        refused.setText("40", of: .weeklySwitch, in: stored)

        // Act
        let changes = try XCTUnwrap(drafts.getChanges(in: stored))

        // Assert
        XCTAssertEqual(changes.autoSwitch?.weeklyThresholdPercent, 85)
        XCTAssertEqual(changes.autoSwitch?.sessionThresholdPercent, 90)
        XCTAssertEqual(refused.getState(.weeklySwitch, in: stored).reason, "from 50% to 100%")
        XCTAssertTrue(refused.getState(.weeklySwitch, in: stored).isRefusedDraft)
    }

    func testPortAndSettleOutsideTheirRangesNameIt() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("80", of: .port, in: stored)
        drafts.setText("700", of: .settle, in: stored)

        // Act
        let canApply = drafts.canApply(in: stored)

        // Assert
        XCTAssertFalse(canApply)
        XCTAssertEqual(drafts.getState(.port, in: stored).reason, "from 1024 to 65535")
        XCTAssertEqual(drafts.getState(.settle, in: stored).reason, "from 0 to 600 s")
        XCTAssertTrue(drafts.getState(.port, in: stored).isRefusedDraft)
        XCTAssertTrue(drafts.getState(.settle, in: stored).isRefusedDraft)
    }

    func testAnOldStoredValueShowsItsReasonWithoutBlockingOtherDrafts() throws {
        // Arrange
        var stored = settings()
        stored.autoSwitch.sessionThresholdPercent = 49
        let drafts = SettingsDrafts()
        drafts.setText("9000", of: .port, in: stored)

        // Act
        let changes = try XCTUnwrap(drafts.getChanges(in: stored))

        // Assert
        XCTAssertEqual(drafts.getState(.sessionSwitch, in: stored).reason, "from 50% to 100%")
        XCTAssertEqual(changes.gatewayPort, 9000)
        XCTAssertNil(changes.autoSwitch)
    }

    func testADraftOfAThresholdThatIsOffIsIgnored() {
        // Arrange
        let stored = settings(save: nil)
        let drafts = SettingsDrafts()
        drafts.setText("80", of: .contextSave, in: stored)

        // Act
        let pending = drafts.hasPending(in: stored)

        // Assert
        XCTAssertFalse(pending)
        XCTAssertEqual(drafts.getBounds(.contextWarn, in: stored).getStepRange(), 10...94)
    }

    func testTheSettingsWindowHasOneApplyUnderTheTabsAndAsksOnClose() throws {
        // Arrange
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let read = { (path: String) in try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }

        // Act
        let window = try read("Sources/Hats/SettingsWindow.swift")
        let fields = try ["PercentField", "GatewaySettleRow", "GatewayPanel"].map { try read("Sources/Hats/\($0).swift") }

        // Assert
        XCTAssertTrue(window.contains("""
                    }
                    HStack {
                        Spacer()
                        Button("Apply") { drafts.apply(model) }
                            .disabled(!drafts.canApply(in: model.snapshot.settings))
                    }
        """))
        XCTAssertTrue(window.contains("func windowShouldClose(_ sender: NSWindow) -> Bool {"))
        for source in fields {
            XCTAssertFalse(source.contains("Button(\"Apply\")"), "a field has no Apply of its own")
            XCTAssertTrue(source.contains("submit: { drafts.apply(model) }"), "Enter presses the shared Apply")
        }
    }
}
