import XCTest
@testable import Hats

final class SettingsDraftsTests: XCTestCase {
    private func settings(warn: Int? = 60, save: Int? = 70) -> AppSettings {
        var made = AppSettings()
        made.contextThresholds.warnPercent = warn
        made.contextThresholds.savePercent = save
        made.autoSwitch.sessionThresholdPercent = 90
        made.gatewaySettleSeconds = 35
        made.codexAutoSwitch.sessionThresholdPercent = 90
        made.codexAutoSwitch.weeklyThresholdPercent = 95

        return made
    }

    private func model(isPortMoved: Bool = true) -> (HatsModel, RecordingActions) {
        let model = HatsModel()
        model.snapshot.settings = settings()
        let actions = RecordingActions(model: model, isPortMoved: isPortMoved)
        model.actions = actions

        return (model, actions)
    }

    func testEnterWritesOnlyItsOwnFieldAndKeepsTheOtherDraft() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        drafts.setText("75", of: .contextSave, in: model.snapshot.settings)
        drafts.setText("20", of: .settle, in: model.snapshot.settings)

        // Act
        drafts.apply(.contextSave, model)

        // Assert
        XCTAssertEqual(actions.calls, ["context 60 75"])
        XCTAssertEqual(model.snapshot.settings.contextThresholds.savePercent, 75)
        XCTAssertEqual(Array(drafts.drafts.keys), [.settle], "the other field's draft stays")
        XCTAssertEqual(drafts.getText(.settle, in: model.snapshot.settings), "20")
        XCTAssertEqual(model.snapshot.settings.gatewaySettleSeconds, 35)
    }

    func testARefusedNumberIsNotWrittenAndStaysWithItsReason() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        drafts.setText("55", of: .contextSave, in: model.snapshot.settings)

        // Act
        drafts.apply(.contextSave, model)

        // Assert
        let state = drafts.getState(.contextSave, in: model.snapshot.settings)
        XCTAssertEqual(actions.calls, [])
        XCTAssertNil(drafts.getChanges(.contextSave, in: model.snapshot.settings))
        XCTAssertEqual(state.text, "55")
        XCTAssertEqual(state.reason, "above Warn at 60%")
        XCTAssertTrue(state.isRefusedDraft)
    }

    func testThePairIsJudgedAgainstTheStoredNeighbourNotItsDraft() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        drafts.setText("50", of: .contextSave, in: model.snapshot.settings)
        drafts.setText("75", of: .contextWarn, in: model.snapshot.settings)

        // Act
        drafts.apply(.contextWarn, model)

        // Assert
        XCTAssertEqual(actions.calls, [], "75 is above the stored 70, whatever the save field holds")
        XCTAssertEqual(drafts.getState(.contextWarn, in: model.snapshot.settings).reason, "below Anchor at 70%")
        XCTAssertEqual(drafts.getState(.contextSave, in: model.snapshot.settings).reason, "above Warn at 60%")
        XCTAssertEqual(drafts.getBounds(.contextWarn, in: model.snapshot.settings).getStepRange(), 10...69)
    }

    func testTwoFieldsAppliedOneAfterTheOtherMoveThePairUp() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        drafts.setText("85", of: .contextSave, in: model.snapshot.settings)
        drafts.apply(.contextSave, model)
        drafts.setText("75", of: .contextWarn, in: model.snapshot.settings)

        // Act
        drafts.apply(.contextWarn, model)

        // Assert
        XCTAssertEqual(actions.calls, [
            "context 60 85",
            "context 75 85",
        ])
        XCTAssertEqual(drafts.drafts, [:])
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

    func testTextEqualToTheStoredValueIsNoDraft() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("70", of: .contextSave, in: stored)
        drafts.setText("060", of: .contextWarn, in: stored)

        // Act
        let changes = SettingsField.allCases.compactMap { drafts.getChanges($0, in: stored) }

        // Assert
        XCTAssertEqual(changes, [])
        XCTAssertTrue(drafts.getLeftovers(in: stored).isEmpty)
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

    func testEscBringsBackTheStoredValueAndTheFocusLeavingAfterItWritesNothing() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        drafts.setText("65", of: .contextSave, in: model.snapshot.settings)

        // Act
        drafts.reset(.contextSave)
        drafts.apply(.contextSave, model)

        // Assert
        XCTAssertEqual(drafts.getText(.contextSave, in: model.snapshot.settings), "70")
        XCTAssertNil(drafts.drafts[.contextSave])
        XCTAssertEqual(actions.calls, [])
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

    func testTheCloseQuestionNamesARefusedNumberAndOffersDiscardAndCancelOnly() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("80", of: .port, in: stored)

        // Act
        let prompt = SettingsCloseQuestion.getPrompt(drafts.getLeftovers(in: stored))

        // Assert
        XCTAssertFalse(drafts.getLeftovers(in: stored).isEmpty)
        XCTAssertEqual(prompt.text, "Gateway port 80: from 1024 to 65535\nDiscard them, or cancel and fix them.")
        XCTAssertEqual(prompt.buttons, ["Discard", "Cancel"])
        XCTAssertEqual(SettingsCloseQuestion.answers, [.discard, .cancel])
        XCTAssertEqual(SettingsCloseQuestion.getAnswer(at: 0), .discard)
        XCTAssertEqual(SettingsCloseQuestion.getAnswer(at: 1), .cancel)
        XCTAssertEqual(SettingsCloseQuestion.getAnswer(at: 2), .cancel, "out of range is cancel")
        XCTAssertEqual(SettingsCloseQuestion.getAnswer(at: -1), .cancel)
    }

    func testClosingWithNothingLeftDoesNotAsk() {
        // Arrange
        var calls: [String] = []

        // Act
        let closes = SettingsCloseQuestion.canClose(
            leftovers: [],
            ask: { _ in
                calls.append("ask")
                return .cancel
            },
            discard: { calls.append("discard") }
        )

        // Assert
        XCTAssertTrue(closes)
        XCTAssertEqual(calls, [], "nothing left: the window closes without a question")
    }

    func testDiscardClosesAndDropsTheNumbersCancelKeepsTheWindowAndThem() {
        // Arrange
        let left = [SettingsLeftover(name: "Settle", text: "700", reason: "from 0 to 600 s")]
        var calls: [String] = []
        let discard = { calls.append("discard") }

        // Act
        let discarded = SettingsCloseQuestion.canClose(leftovers: left, ask: { _ in .discard }, discard: discard)
        let afterDiscard = calls
        let cancelled = SettingsCloseQuestion.canClose(leftovers: left, ask: { _ in .cancel }, discard: discard)

        // Assert
        XCTAssertTrue(discarded)
        XCTAssertEqual(afterDiscard, ["discard"])
        XCTAssertFalse(cancelled, "Cancel keeps the window open")
        XCTAssertEqual(calls, ["discard"], "Cancel drops nothing")
    }

    func testTheWindowClosesThroughTheDecisionAfterTheFocusedFieldIsWritten() throws {
        // Arrange
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

        // Act
        let window = try String(contentsOf: root.appendingPathComponent("Sources/Hats/SettingsWindow.swift"), encoding: .utf8)

        // Assert
        let focus = try XCTUnwrap(window.range(of: "sender.makeFirstResponder(nil)"))
        let decision = try XCTUnwrap(window.range(of: "return SettingsCloseQuestion.canClose("))
        XCTAssertLessThan(focus.lowerBound, decision.lowerBound, "the focused field is written before the leftovers are read")
    }

    func testTheCloseQuestionShortensAVeryLongPastedNumberAndKeepsItsReason() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText(String(repeating: "9", count: 5000), of: .settle, in: stored)

        // Act
        let prompt = SettingsCloseQuestion.getPrompt(drafts.getLeftovers(in: stored))

        // Assert
        XCTAssertEqual(
            prompt.text,
            "Settle 99999999…: from 0 to 600 s\nDiscard them, or cancel and fix them.",
            "a pasted wall of digits must not push the buttons off the screen"
        )
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

    func testEachFieldGoesToItsOwnAction() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        let fields: [(SettingsField, String)] = [
            (.port, "9000"),
            (.settle, "20"),
            (.weeklySwitch, "85"),
            (.contextSave, "65"),
            (.limitWarn, "75"),
        ]
        for (field, text) in fields {
            drafts.setText(text, of: field, in: model.snapshot.settings)
        }

        // Act
        for (field, _) in fields {
            drafts.apply(field, model)
        }

        // Assert
        XCTAssertEqual(actions.calls, [
            "port 9000",
            "settle 20",
            "autoSwitch 90 85",
            "context 60 65",
            "limits 75 80",
        ])
        XCTAssertEqual(drafts.drafts, [:])
    }

    func testARefusedPortMoveKeepsThePortDraft() {
        // Arrange
        let (model, actions) = model(isPortMoved: false)
        let drafts = SettingsDrafts()
        drafts.setText("9000", of: .port, in: model.snapshot.settings)
        drafts.setText("20", of: .settle, in: model.snapshot.settings)

        // Act
        drafts.apply(.port, model)
        drafts.apply(.settle, model)

        // Assert
        XCTAssertEqual(actions.calls, [
            "port 9000",
            "settle 20",
        ])
        XCTAssertEqual(Array(drafts.drafts.keys), [.port])
        XCTAssertEqual(drafts.getText(.port, in: model.snapshot.settings), "9000")
        XCTAssertFalse(drafts.getLeftovers(in: model.snapshot.settings).isEmpty, "the window asks before closing over the refusal")
    }

    func testCodexDraftsGoToTheCodexActionsAndLeaveTheClaudeOnesAlone() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        let stored = model.snapshot.settings
        drafts.setText("1460", of: .codexPort, in: stored)
        drafts.setText("80", of: .codexSessionSwitch, in: stored)
        drafts.setText("85", of: .weeklySwitch, in: stored)

        // Act
        drafts.apply(.codexPort, model)
        drafts.apply(.weeklySwitch, model)
        drafts.apply(.codexSessionSwitch, model)

        // Assert
        XCTAssertEqual(actions.calls, [
            "codexPort 1460",
            "autoSwitch 90 85",
            "codexAutoSwitch 80 95",
        ])
        XCTAssertEqual(model.snapshot.settings.codexGatewayPort, 1460)
        XCTAssertEqual(model.snapshot.settings.autoSwitch.sessionThresholdPercent, 90)
        XCTAssertEqual(drafts.drafts, [:])
    }

    func testARefusedCodexPortMoveKeepsOnlyTheCodexPortDraft() {
        // Arrange
        let (model, actions) = model(isPortMoved: false)
        let drafts = SettingsDrafts()
        let stored = model.snapshot.settings
        drafts.setText("1460", of: .codexPort, in: stored)
        drafts.setText("85", of: .codexWeeklySwitch, in: stored)

        // Act
        drafts.apply(.codexPort, model)
        drafts.apply(.codexWeeklySwitch, model)

        // Assert
        XCTAssertEqual(actions.calls, [
            "codexPort 1460",
            "codexAutoSwitch 90 85",
        ])
        XCTAssertEqual(Array(drafts.drafts.keys), [.codexPort])
        XCTAssertEqual(drafts.getText(.codexPort, in: model.snapshot.settings), "1460")
        XCTAssertEqual(model.snapshot.settings.codexAutoSwitch.weeklyThresholdPercent, 85)
    }

    func testCodexFieldsAreRefusedOutsideTheirRanges() {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()

        // Act
        drafts.setText("40", of: .codexSessionSwitch, in: stored)
        drafts.setText("80", of: .codexPort, in: stored)

        // Assert
        XCTAssertEqual(drafts.getState(.codexSessionSwitch, in: stored).reason, "from 50% to 100%")
        XCTAssertTrue(drafts.getState(.codexPort, in: stored).isRefusedDraft)
        XCTAssertNil(drafts.getChanges(.codexPort, in: stored))
    }

    func testTheLimitPairMovesUpOneFieldAtATime() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        drafts.setText("85", of: .limitWarn, in: model.snapshot.settings)
        drafts.apply(.limitWarn, model)
        drafts.setText("90", of: .limitSave, in: model.snapshot.settings)

        // Act
        drafts.apply(.limitSave, model)

        // Assert
        XCTAssertEqual(actions.calls, [
            "limits 70 90",
            "limits 85 90",
        ], "85 waits above the stored 80 until save has moved to 90, then is written by itself")
        XCTAssertEqual(drafts.drafts, [:])
    }

    func testThePartnerDraftThatBecameUsableIsWrittenToo() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        drafts.setText("75", of: .contextWarn, in: model.snapshot.settings)
        drafts.apply(.contextWarn, model)
        drafts.setText("85", of: .contextSave, in: model.snapshot.settings)

        // Act
        drafts.apply(.contextSave, model)

        // Assert
        XCTAssertEqual(actions.calls, [
            "context 60 85",
            "context 75 85",
        ])
        XCTAssertEqual(model.snapshot.settings.contextThresholds.warnPercent, 75)
        XCTAssertEqual(drafts.drafts, [:])
        XCTAssertTrue(drafts.getLeftovers(in: model.snapshot.settings).isEmpty)
    }

    func testAPartnerDraftStillRefusedAfterTheWriteStaysWithItsReason() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        drafts.setText("50", of: .contextSave, in: model.snapshot.settings)
        drafts.setText("65", of: .contextWarn, in: model.snapshot.settings)

        // Act
        drafts.apply(.contextWarn, model)

        // Assert
        XCTAssertEqual(actions.calls, ["context 65 70"])
        XCTAssertEqual(drafts.getState(.contextSave, in: model.snapshot.settings).reason, "above Warn at 65%")
        XCTAssertEqual(Array(drafts.drafts.keys), [.contextSave])
    }

    func testAPartnerIsNotWrittenWhenItsFieldWasNotWritten() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        drafts.setText("65", of: .contextSave, in: model.snapshot.settings)
        drafts.setText("75", of: .contextWarn, in: model.snapshot.settings)

        // Act
        drafts.apply(.contextWarn, model)

        // Assert
        XCTAssertEqual(actions.calls, [], "warn 75 is refused, so the usable save draft waits for its own Enter")
        XCTAssertEqual(drafts.drafts[.contextSave]?.text, "65")
    }

    func testAnEmptyFieldSubmittedShowsTheStoredValueAgain() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        drafts.setText("", of: .settle, in: model.snapshot.settings)

        // Act
        drafts.apply(.settle, model)

        // Assert
        XCTAssertEqual(actions.calls, [])
        XCTAssertNil(drafts.drafts[.settle])
        XCTAssertEqual(drafts.getText(.settle, in: model.snapshot.settings), "35")
    }

    func testTheArrowsWriteThePartnerDraftThatBecameUsable() {
        // Arrange
        let (model, actions) = model()
        let drafts = SettingsDrafts()
        drafts.setText("75", of: .contextWarn, in: model.snapshot.settings)
        drafts.apply(.contextWarn, model)
        var stepped = model.snapshot.settings.contextThresholds
        stepped.savePercent = 85
        actions.updateContextThresholds(stepped)

        // Act
        drafts.applyPartner(of: .contextSave, model)

        // Assert
        XCTAssertEqual(actions.calls, [
            "context 60 85",
            "context 75 85",
        ])
        XCTAssertEqual(drafts.getLeftovers(in: model.snapshot.settings), [])
    }

    func testOnlyThePairsArePartners() {
        // Arrange
        let pairs = SettingsField.allCases.map { ($0, SettingsDrafts.getPartner($0)) }

        // Act
        let partnered = pairs.filter { $0.1 != nil }

        // Assert
        XCTAssertEqual(partnered.map(\.0), [.contextWarn, .contextSave, .limitWarn, .limitSave])
        XCTAssertEqual(partnered.map(\.1), [.contextSave, .contextWarn, .limitSave, .limitWarn])
    }

    func testTheCloseQuestionNamesAPortTheGatewayRefused() {
        // Arrange
        let (model, actions) = model(isPortMoved: false)
        let drafts = SettingsDrafts()
        drafts.setText("9000", of: .port, in: model.snapshot.settings)
        drafts.apply(.port, model)

        // Act
        let prompt = SettingsCloseQuestion.getPrompt(drafts.getLeftovers(in: model.snapshot.settings))

        // Assert
        XCTAssertEqual(prompt.text, "Gateway port 9000: was not applied\nDiscard them, or cancel and fix them.")
        XCTAssertEqual(actions.calls, ["port 9000"], "building the question does not move the port again")
    }

    func testTheWeeklyAutoSwitchFieldIsAppliedAndRefused() throws {
        // Arrange
        let stored = settings()
        let drafts = SettingsDrafts()
        drafts.setText("85", of: .weeklySwitch, in: stored)
        let refused = SettingsDrafts()
        refused.setText("40", of: .weeklySwitch, in: stored)

        // Act
        let changes = try XCTUnwrap(drafts.getChanges(.weeklySwitch, in: stored))

        // Assert
        XCTAssertNil(refused.getChanges(.weeklySwitch, in: stored))
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
        let changes = [drafts.getChanges(.port, in: stored), drafts.getChanges(.settle, in: stored)]

        // Assert
        XCTAssertEqual(changes, [nil, nil])
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
        let changes = try XCTUnwrap(drafts.getChanges(.port, in: stored))

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
        let leftovers = drafts.getLeftovers(in: stored)

        // Assert
        XCTAssertEqual(leftovers, [])
        XCTAssertEqual(drafts.getBounds(.contextWarn, in: stored).getStepRange(), 10...94)
    }

    func testTheSettingsWindowHasNoApplyAndEachFieldAppliesItselfOnEnterOrFocusLoss() throws {
        // Arrange
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let read = { (path: String) in try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
        let fields: [(String, String)] = [
            ("PercentField", "field"),
            ("GatewaySettleRow", ".settle"),
            ("GatewayPanel", ".port"),
            ("CodexGatewayPanel", ".codexPort"),
        ]

        // Act
        let window = try read("Sources/Hats/SettingsWindow.swift")
        let digit = try read("Sources/Hats/DigitField.swift")
        let sources = try fields.map { (try read("Sources/Hats/\($0.0).swift"), $0.1) }
        let block = try read("Sources/Hats/AutoSwitchBlock.swift")

        // Assert
        XCTAssertFalse(window.contains("Button(\"Apply\")"), "the window has no Apply")
        XCTAssertTrue(window.contains(".frame(width: 460, height: 456)"))
        XCTAssertTrue(window.contains("""
            func windowShouldClose(_ sender: NSWindow) -> Bool {
                sender.makeFirstResponder(nil)
        """), "closing ends the edit of the focused field, which applies it")
        XCTAssertTrue(digit.contains("func controlTextDidEndEditing(_ notification: Notification) {"),
                      "the focus leaving a field applies it")
        for (source, field) in sources {
            XCTAssertFalse(source.contains("Button(\"Apply\")"), "a field has no Apply of its own")
            XCTAssertTrue(source.contains("submit: { drafts.apply(\(field), model) }"), "Enter applies its own field")
        }
        XCTAssertTrue(sources[0].0.contains("step(stepRange.getClamped(value))\n"
                                                + "                        drafts.applyPartner(of: field, model)"),
                      "the arrows write the partner the same way Enter does")
        XCTAssertTrue(block.contains("PercentField("), "both auto-switch blocks take typed percents")
        XCTAssertFalse(block.contains("Stepper("), "the steppers live in PercentField only")
    }
}
