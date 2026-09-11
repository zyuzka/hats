import XCTest
@testable import Hats

final class GatewaySettleTests: XCTestCase {
    func testTheSettleDefaultsToTheShippedValueAndSurvivesAnOlderFile() throws {
        XCTAssertEqual(AppSettings().gatewaySettleSeconds, 35)
        let older = Data(#"{"gatewayPort":8787}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: older).gatewaySettleSeconds, 35,
                       "a settings file written before this setting existed keeps the measured value")
        let written = Data(#"{"gatewaySettleSeconds":null}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: written).gatewaySettleSeconds, 35,
                       "an absent key and a written null are the same absence, and absence is 35 rather than 0")
    }

    func testAnUnusableSettleFallsBackRatherThanShippingAsWritten() throws {
        for written in [-1, 601, 100_000] {
            let raw = Data("{\"gatewaySettleSeconds\":\(written)}".utf8)
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: raw).gatewaySettleSeconds, 35,
                           "\(written) is not a settle this app will hand to the refusal")
        }
        for written in [0, 2, 35, 600] {
            let raw = Data("{\"gatewaySettleSeconds\":\(written)}".utf8)
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: raw).gatewaySettleSeconds, written)
        }
    }

    func testTheRangeIsTheOnePlaceThatDecidesWhatIsUsable() {
        XCTAssertFalse(AppSettings.isAUsableSettle(-1))
        XCTAssertFalse(AppSettings.isAUsableSettle(601))
        XCTAssertTrue(AppSettings.isAUsableSettle(0))
        XCTAssertTrue(AppSettings.isAUsableSettle(600))
    }

    func testTheDelayIsStatedFromTheSettleRatherThanFromAConstant() {
        XCTAssertEqual(HatsCopy.followsASwitch(settleSeconds: 35),
                       "at its first request 35 s after a switch, about 45 s in practice")
        XCTAssertEqual(HatsCopy.followsASwitch(settleSeconds: 2),
                       "at its first request 2 s after a switch, about 12 s in practice",
                       "three panels and the sessions table read this one sentence; a hard-coded 45 "
                           + "would start lying the moment the setting moved")
        XCTAssertEqual(HatsCopy.followsASwitch(settleSeconds: 0),
                       "at its next request after a switch",
                       "zero means no settle at all, and saying '0 s after a switch' would be odd")
    }

    func testShorteningTheSettleCarriesItsWarningAndLengtheningDoesNot() {
        XCTAssertNil(HatsCopy.settleWarning(settleSeconds: 35))
        XCTAssertNil(HatsCopy.settleWarning(settleSeconds: 120))
        let short = HatsCopy.settleWarning(settleSeconds: 5)
        XCTAssertNotNil(short)
        XCTAssertEqual(short?.contains("credential cache"), true,
                       "the reason is the CLI's own cache, and the warning has to name it: \(short ?? "nil")")
        XCTAssertEqual(short?.contains("one measurement"), true,
                       "and it says how much is known, since one live switch is what stands behind it")
        XCTAssertEqual(short?.contains("CLAUDE_CODE_OAUTH_401_WAIT_MS"), false,
                       "that variable cannot help a local session: the wait is gated on a token from "
                           + "the environment or from a path inside the remote container, so naming "
                           + "it here would send the reader after a cure that does not exist")
    }

    func testAWarningIsNotShownForAValueApplyWouldRefuse() {
        XCTAssertNil(HatsCopy.settleWarning(settleSeconds: -5),
                     "-5 is below 35 and also unusable; warning about the CLI cache for a value the "
                         + "Apply button refuses tells the user about a setting that cannot exist")
        XCTAssertNil(HatsCopy.settleWarning(settleSeconds: 700))
        XCTAssertNotNil(HatsCopy.settleWarning(settleSeconds: 0), "zero is usable and is below 35")
        XCTAssertNotNil(HatsCopy.settleWarning(settleSeconds: 34))
    }

    func testTypedTextBecomesAValueOnlyWhenItIsUsableAndDifferent() {
        let usable = AppSettings.isAUsableSettle
        XCTAssertEqual(TypedNumber.applicable("7", current: 35, isUsable: usable), 7)
        XCTAssertEqual(TypedNumber.applicable("  7 ", current: 35, isUsable: usable), 7,
                       "a field people type into carries whitespace")
        XCTAssertNil(TypedNumber.applicable("35", current: 35, isUsable: usable), "unchanged is nothing to apply")
        XCTAssertNil(TypedNumber.applicable("601", current: 35, isUsable: usable))
        XCTAssertNil(TypedNumber.applicable("-1", current: 35, isUsable: usable))
        XCTAssertNil(TypedNumber.applicable("", current: 35, isUsable: usable))
        XCTAssertNil(TypedNumber.applicable("abc", current: 35, isUsable: usable))
        XCTAssertEqual(TypedNumber.applicable("9000", current: 8787, isUsable: AppSettings.isAUsablePort), 9000,
                       "the port field asks the same question of a different range")
    }

    func testEachPanelSentenceIsDerivedAndNamesTheSwitchOnce() {
        XCTAssertEqual(
            HatsCopy.gatewayRunDetail(.running, settleSeconds: 2),
            "serving — a session started through it moves at its first request 2 s after a switch, "
                + "about 12 s in practice"
        )
        XCTAssertEqual(HatsCopy.gatewayRunDetail(.notRunning, settleSeconds: 2),
                       "off — hats change at the next renewal")
        XCTAssertEqual(HatsCopy.gatewayRunDetail(.failed("port 8787 is taken"), settleSeconds: 2),
                       "could not start: port 8787 is taken")
        XCTAssertEqual(
            HatsCopy.whenSessionsChangeHats(settleSeconds: 0),
            "Sessions started through the gateway change at its next request after a switch; "
                + "every other session at its next token renewal."
        )
        for sentence in [HatsCopy.gatewayRunDetail(.running, settleSeconds: 35),
                         HatsCopy.whenSessionsChangeHats(settleSeconds: 35)] {
            XCTAssertEqual(sentence.components(separatedBy: "switch").count - 1, 1,
                           "the panel prefix used to say switch immediately before the shared tail "
                               + "said it again: \(sentence)")
        }
    }

    func testTheFieldsParseTypedTextInOnePlace() {
        XCTAssertEqual(TypedNumber.typed("  7 "), 7, "a field people type into carries whitespace")
        XCTAssertEqual(TypedNumber.typed("8787\n"), 8787,
                       "a pasted value carries the newline it was copied with, and refusing it would "
                           + "leave Apply disabled over a number that is perfectly good")
        XCTAssertEqual(TypedNumber.typed("35"), 35)
        XCTAssertNil(TypedNumber.typed(""))
        XCTAssertNil(TypedNumber.typed("abc"))
        XCTAssertEqual(TypedNumber.applicable("  7 ", current: 35, isUsable: AppSettings.isAUsableSettle),
                       TypedNumber.typed("  7 "),
                       "both answer the same on whitespace. That they answer from ONE parse is held by "
                           + "the source, not by this test: a second parse inside applicable would pass "
                           + "here as long as it happened to agree")
    }

    func testTheSessionsTableFollowsTheSettingAndNotTheDefault() {
        let live = [Session(pid: 1, elapsed: "1m", isInteractive: true,
                            route: .pointedAt("http://127.0.0.1:8787"))]
        let quick = LiveSessionRow.rows(
            sessions: live,
            wearingTitle: "Work",
            gateway: .init(addresses: .of(currentPort: 8787, retiredPort: nil),
                           isServing: true, settleSeconds: 2),
            horizon: ""
        )
        XCTAssertEqual(quick.first?.moves,
                       "through the gateway — at its first request 2 s after a switch, about 12 s in practice")
    }
}
