import XCTest
@testable import Hats

final class TypedNumberTests: XCTestCase {
    private func window(_ warn: Int?, _ save: Int?) -> ContextThresholds {
        var made = ContextThresholds()
        made.warnPercent = warn
        made.savePercent = save

        return made
    }

    private func decide(_ text: String, current: Int, bounds: PercentBounds) -> (PercentDecision, String?) {
        let decision = TypedNumber.getPercentDecision(text, current: current, bounds: bounds)
        guard case .refuse(let refusal) = decision else { return (decision, nil) }

        return (decision, HatsCopy.getPercentRefusal(refusal, bounds: bounds))
    }

    private let autoSwitch = PercentBounds(AutoSwitchPolicy.thresholdRange)

    func testAUsableNumberIsAppliedAsTyped() {
        let (decision, reason) = decide("65", current: 70, bounds: window(60, 70).getSaveBounds())

        XCTAssertEqual(decision, .apply(65))
        XCTAssertNil(reason)
    }

    func testABoundSetByTheOtherThresholdNamesIt() {
        let (decision, reason) = decide("55", current: 70, bounds: window(60, 70).getSaveBounds())

        XCTAssertEqual(decision, .refuse(.belowLower))
        XCTAssertEqual(reason, "above Warn at 60%")
        XCTAssertEqual(decide("70", current: 60, bounds: window(60, 70).getWarnBounds()).1, "below Anchor at 70%")
    }

    func testWithTheOtherThresholdOffTheRangeIsNamedWithoutIt() {
        let (decision, reason) = decide("95", current: 60, bounds: window(60, nil).getWarnBounds())

        XCTAssertEqual(decision, .refuse(.aboveUpper))
        XCTAssertEqual(reason, "from 10% to 94%")
        XCTAssertEqual(
            decide("5", current: 60, bounds: window(60, 70).getWarnBounds()).1,
            "from 10% to 69%",
            "the lower edge is the range's own, so the range is named even with the anchor on"
        )
    }

    func testARangeOfOneNumberNamesTheEdgeThatWasCrossed() {
        let bounds = window(10, 11).getWarnBounds()

        XCTAssertEqual(decide("9", current: 10, bounds: bounds).1, "from 10% to 10%")
        XCTAssertEqual(decide("11", current: 10, bounds: bounds).1, "below Anchor at 11%")
        XCTAssertEqual(decide("10", current: 10, bounds: bounds).0, .silent)
    }

    func testOutsideTheAutoSwitchRange() {
        XCTAssertEqual(decide("5", current: 90, bounds: autoSwitch).1, "from 50% to 100%")
        XCTAssertEqual(decide("101", current: 90, bounds: autoSwitch).1, "from 50% to 100%")
        XCTAssertEqual(decide("100", current: 90, bounds: autoSwitch).0, .apply(100))
        XCTAssertEqual(decide("50", current: 90, bounds: autoSwitch).0, .apply(50))
    }

    func testANumberTooBigForAnIntIsRefusedAtTheUpperBound() {
        let digits = "99999999999999999999"

        XCTAssertNil(Int(digits), "the case only exists while the text does not fit an Int")
        XCTAssertEqual(decide(digits, current: 90, bounds: autoSwitch).0, .refuse(.aboveUpper))
        XCTAssertEqual(decide(digits, current: 60, bounds: window(60, 70).getWarnBounds()).1, "below Anchor at 70%")
        XCTAssertEqual(decide("-" + digits, current: 90, bounds: autoSwitch).0, .refuse(.belowLower))
    }

    func testTextThatIsNotAWholeNumberIsRefused() {
        for text in ["abc", "6.5", "7%", "-", "+", "1 2"] {
            let (decision, reason) = decide(text, current: 90, bounds: autoSwitch)

            XCTAssertEqual(decision, .refuse(.notAWholeNumber), text)
            XCTAssertEqual(reason, "a whole number", text)
        }
    }

    func testASignOrALeadingZeroStillReadsAsTheNumber() {
        XCTAssertEqual(decide("+5", current: 90, bounds: autoSwitch).1, "from 50% to 100%")
        XCTAssertEqual(decide("+55", current: 90, bounds: autoSwitch).0, .apply(55))
        XCTAssertEqual(decide("070", current: 90, bounds: autoSwitch).0, .apply(70))
        XCTAssertEqual(decide("+99999999999999999999", current: 90, bounds: autoSwitch).0, .refuse(.aboveUpper))
    }

    func testTheFieldShowsTheRefusalOverTheNoteAndAppliesOnlyANewUsableNumber() {
        let note = "Warn at 95% leaves no room above it: lower Warn at first"
        let state = { (text: String, current: Int?) in
            TypedNumber.getPercentFieldState(text, current: current, bounds: self.autoSwitch, note: note)
        }

        XCTAssertEqual(
            state("5", 90),
            PercentFieldState(reason: "from 50% to 100%", applicable: nil),
            "a refusal hides the note"
        )
        XCTAssertEqual(state("90", 90), PercentFieldState(reason: note, applicable: nil))
        XCTAssertEqual(state("", 90), PercentFieldState(reason: note, applicable: nil))
        XCTAssertEqual(
            state("70", nil),
            PercentFieldState(reason: note, applicable: nil),
            "a threshold that is off has no field, only its note"
        )
        XCTAssertEqual(state("70", 90), PercentFieldState(reason: note, applicable: 70))
        XCTAssertEqual(
            TypedNumber.getPercentFieldState("70", current: 90, bounds: autoSwitch, note: nil),
            PercentFieldState(reason: nil, applicable: 70)
        )
    }

    func testEmptyBlankAndCurrentTextSayNothing() {
        let bounds = window(60, 70).getSaveBounds()
        for text in ["", "   ", "70", " 70\n"] {
            let (decision, reason) = decide(text, current: 70, bounds: bounds)

            XCTAssertEqual(decision, .silent, "'\(text)'")
            XCTAssertNil(reason, "'\(text)'")
        }
    }

    func testAnOldValueOutsideTheRangeIsShownWithItsReasonAndCanBeFixed() {
        let (decision, reason) = decide("49", current: 49, bounds: autoSwitch)

        XCTAssertEqual(decision, .refuse(.belowLower), "the current value is checked before it is called unchanged")
        XCTAssertEqual(reason, "from 50% to 100%")
        XCTAssertEqual(decide("50", current: 49, bounds: autoSwitch).0, .apply(50))
    }

    func testAnOldAutoSwitchValueIsReadAsItIs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hats-typed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("settings.json")
        let json = #"{"autoSwitch": {"isOn": true, "notifies": true, "order": [], "sessionThresholdPercent": 49}}"#
        try Data(json.utf8).write(to: url)

        XCTAssertEqual(AppSettings.loaded(from: url).autoSwitch.sessionThresholdPercent, 49)
    }
}
