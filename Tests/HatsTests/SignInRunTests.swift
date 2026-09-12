import XCTest
@testable import Hats

final class SignInRunTests: XCTestCase {
    private func command(_ executable: String, _ arguments: [String]) -> SignInCommand {
        SignInCommand(executable: executable, arguments: arguments, environment: [:])
    }

    private func endingOf(_ run: SignInRun, _ command: SignInCommand) throws -> SignInRun.Ending {
        let ended = expectation(description: "the sign-in ended")
        var seen: SignInRun.Ending?
        run.ended = { seen = $0; ended.fulfill() }

        try run.start(command)
        wait(for: [ended], timeout: 10)

        return try XCTUnwrap(seen)
    }

    func testWhatTheCommandPrintsReachesTheTranscript() throws {
        let run = SignInRun()

        let ending = try endingOf(run, command("/bin/echo", ["Paste code here"]))

        XCTAssertEqual(ending, .signedIn)
        XCTAssertTrue(run.transcript.text.contains("Paste code here"))
        XCTAssertTrue(run.transcript.awaitsTheCode,
                      "the transcript is read as it arrives, so the window knows to ask without "
                          + "waiting for the command to finish")
    }

    func testACommandThatFailsCarriesItsStatusRatherThanASignedInVerdict() throws {
        let run = SignInRun()

        let ending = try endingOf(run, command("/bin/sh", ["-c", "exit 3"]))

        XCTAssertEqual(ending, .failed(3),
                       "a non-zero exit is the only thing that separates a refused sign-in from a "
                           + "successful one, and calling it success would store nothing and say "
                           + "it worked")
    }

    func testTheCodeAPersonTypesReachesTheCommandsInput() throws {
        let run = SignInRun()
        let echoed = expectation(description: "the code came back out")
        run.changed = { transcript in
            guard transcript.text.contains("a-pasted-code") else { return }
            echoed.fulfill()
        }

        try run.start(command("/bin/cat", []))
        run.send("a-pasted-code")
        wait(for: [echoed], timeout: 10)

        run.cancel()
    }

    func testCancellingEndsTheRunAndStopsTheProcess() throws {
        let run = SignInRun()
        let ended = expectation(description: "the sign-in ended")
        var seen: SignInRun.Ending?
        run.ended = { seen = $0; ended.fulfill() }

        try run.start(command("/bin/cat", []))
        run.cancel()
        wait(for: [ended], timeout: 10)

        XCTAssertEqual(seen, .cancelled,
                       "a cancelled sign-in is not a failed one: the window closes without an "
                           + "error, and nothing is stored either way")
        XCTAssertFalse(run.isRunning)
    }
}
