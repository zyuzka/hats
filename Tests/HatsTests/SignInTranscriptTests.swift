import XCTest
@testable import Hats

final class SignInTranscriptTests: XCTestCase {
    private let opening = "Opening browser to sign in\u{2026}\n"
    private let visit = "If the browser didn't open, visit: "
        + "https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a&response_type=code"
        + "&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback"
        + "&login_hint=probe%40example.com\n"
    private let prompt = "Paste code here if prompted > "
    private let refused = "Invalid code. Please make sure the full code was copied.\n"

    private func started() -> SignInTranscript {
        var transcript = SignInTranscript()
        transcript.read(opening + visit + prompt)
        return transcript
    }

    func testThePromptIsWhatPutsTheWindowInFrontOfAPerson() {
        XCTAssertTrue(started().awaitsTheCode,
                      "the redirect goes to platform.claude.com rather than a local port, so a "
                          + "person has to paste the code and the window has to ask for it")
    }

    func testNothingReadYetAsksForNothing() {
        XCTAssertFalse(SignInTranscript().awaitsTheCode)
        XCTAssertNil(SignInTranscript().signInURL)
    }

    func testSendingACodeStopsTheAsking() {
        var transcript = started()

        transcript.sent("a-code")

        XCTAssertFalse(transcript.awaitsTheCode)
        XCTAssertTrue(transcript.text.hasSuffix("a-code\n"),
                      "the code a person typed belongs in the transcript, or the log of a failed "
                          + "sign-in cannot show that one was ever sent")
    }

    func testARefusedCodeAsksAgain() {
        var transcript = started()
        transcript.sent("a-code")

        transcript.read(refused)

        XCTAssertTrue(transcript.awaitsTheCode,
                      "the command prints its refusal and keeps the prompt open, so a window that "
                          + "stopped asking would strand a person one keystroke from succeeding")
    }

    func testTheSignInAddressIsTakenFromTheLineThatOffersIt() throws {
        let url = try XCTUnwrap(started().signInURL)

        XCTAssertEqual(url.host, "claude.com")
        XCTAssertTrue(url.absoluteString.contains("login_hint=probe%40example.com"))
        XCTAssertFalse(url.absoluteString.hasSuffix("\n"))
    }

    func testTheAddressSurvivesABrokenUpRead() throws {
        var transcript = SignInTranscript()
        transcript.read(opening + "If the browser didn't open, visit: https://claude.com/cai/")
        transcript.read("oauth/authorize?code=true\n" + prompt)

        let url = try XCTUnwrap(transcript.signInURL)

        XCTAssertEqual(url.absoluteString, "https://claude.com/cai/oauth/authorize?code=true",
                       "a pipe hands over whatever arrived, and a URL split across two reads is "
                           + "the ordinary case rather than a rare one")
    }
}

final class SignInStageTests: XCTestCase {
    func testNothingPrintedYetIsStartingRatherThanWorking() {
        XCTAssertEqual(SignInTranscript().stage, .starting)
        XCTAssertEqual(HatsCopy.signInStage(.starting), "Starting the sign-in\u{2026}")
    }

    func testThePromptIsTheOnlyStageThatAsksAPersonForAnything() {
        var transcript = SignInTranscript()
        transcript.read("Paste code here if prompted > ")

        XCTAssertEqual(transcript.stage, .waitingForTheCode)
        XCTAssertEqual(HatsCopy.signInStage(.waitingForTheCode),
                       "Paste the code the browser page shows, then choose Sign in.")
    }

    func testACodeAlreadySentLeavesTheWindowWithNothingToAskFor() {
        var transcript = SignInTranscript()
        transcript.read("Paste code here if prompted > ")
        transcript.sent("a-code")

        XCTAssertEqual(transcript.stage, .working)
        XCTAssertEqual(HatsCopy.signInStage(.working), "Working\u{2026}")
    }

    func testAFailedSignInNamesTheStatusAndWhereTheOutputWent() {
        XCTAssertEqual(HatsCopy.signInFailed(3),
                       "The sign-in command stopped with status 3. Nothing was stored. The full "
                           + "output is in last-sign-in.log.")
    }
}
