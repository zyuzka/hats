import XCTest
@testable import Hats

final class AutomationVerdictTests: XCTestCase {
    func testGrantedIsTheOnlySilentVerdict() {
        XCTAssertEqual(Automation.Verdict.of(status: 0), .granted)
        XCTAssertNil(Automation.explanation(for: .granted))
    }

    func testRefusalIsItsOwnAnswer() {
        XCTAssertEqual(Automation.Verdict.of(status: -1743), .denied)
    }

    func testTargetNotRunningIsItsOwnAnswer() {
        XCTAssertEqual(Automation.Verdict.of(status: -600), .targetNotRunning,
                       "-600 is procNotFound: there is no process to ask about, which says nothing about permission")
    }

    func testMissingUsageDescriptionIsItsOwnAnswer() {
        XCTAssertEqual(Automation.Verdict.of(status: -1744), .needsUsageDescription)
    }

    func testAnUnrecognisedStatusKeepsItsNumber() {
        XCTAssertEqual(Automation.Verdict.of(status: -12345), .cannotAsk(-12345))
        XCTAssertEqual(Automation.explanation(for: .cannotAsk(-12345))?.contains("-12345"), true)
    }

    func testOnlyTheMissingUsageDescriptionBlamesTheBundle() {
        let blame = "defect in the app bundle"
        XCTAssertEqual(Automation.explanation(for: .needsUsageDescription)?.contains(blame), true,
                       "a missing NSAppleEventsUsageDescription really is a bundle defect")
        for innocent: Automation.Verdict in [.denied, .targetNotRunning, .cannotAsk(-600)] {
            XCTAssertEqual(Automation.explanation(for: innocent)?.contains(blame), false,
                           "\(innocent) is not evidence of a bundle defect and must not be reported as one")
        }
    }

    func testTheDefaultNameIsTheNameTheAppActuallyHas() {
        XCTAssertEqual(Automation.explanation(for: .denied)?.contains("Hats"), true,
                       "the default appName is what a caller that forgets to pass one will show a user")
        XCTAssertEqual(Automation.explanation(for: .denied)?.contains("Claude Accounts"), false,
                       "Claude Accounts is the name this app had before the rename and no longer answers to")
    }

    func testNoVerdictAssertsACauseItsStatusCannotEstablish() {
        for verdict: Automation.Verdict in [.targetNotRunning, .cannotAsk(-600), .cannotAsk(-1)] {
            let text = Automation.explanation(for: verdict) ?? ""
            XCTAssertFalse(text.contains("must have"),
                           "\(verdict) knows the state, not the reason for it, and may not narrate one")
        }
    }

    func testOnlyANonAnswerLeavesTheQuestionOpen() {
        XCTAssertFalse(Automation.isSettled(.targetNotRunning),
                       "procNotFound asked nobody anything, so the next close must be free to ask again")
        for settled: Automation.Verdict in [.granted, .denied, .needsUsageDescription, .cannotAsk(-1)] {
            XCTAssertTrue(Automation.isSettled(settled),
                          "\(settled) is an answer from macOS, and asking again this launch changes nothing")
        }
    }

    func testEveryUngrantedVerdictSaysTheWindowStaysOpen() {
        let ungranted: [Automation.Verdict] = [
            .denied, .targetNotRunning, .needsUsageDescription, .cannotAsk(-1),
        ]
        for verdict in ungranted {
            XCTAssertEqual(Automation.explanation(for: verdict)?.contains("closed by hand"), true,
                           "\(verdict) leaves the window open, and the sentence has to say what the user must do")
        }
    }
}
