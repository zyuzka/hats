import XCTest
@testable import Hats

final class SystemWorldTests: XCTestCase {
    private let real = SystemWorld.real

    func testTheRealHomeAndEnvironmentAreThisProcessOwn() {
        XCTAssertEqual(real.home(), NSHomeDirectory(),
                       "home decides where the CLI's account file is looked for, so a seam wired to "
                           + "anything else would make the switch write a file nobody reads")
        XCTAssertEqual(real.ownEnvironment(), ProcessInfo.processInfo.environment,
                       "and the own environment is the fallback when no session is running — the "
                           + "source the app falls back to when it cannot ask a live CLI")
    }

    func testTheRealSignatureCheckStillRejectsThisProcess() {
        XCTAssertEqual(real.isTheRealCLI(getpid()), false,
                       "the seam has to carry the real requirement, not a closure that answers yes: "
                           + "a wire to { _ in true } would let any process named claude say which "
                           + "keychain slot and which account file are live, and the suite would "
                           + "stay green because nothing else executes this wiring")
    }

    func testTheRealProcessTableAndEnvironmentAnswer() {
        XCTAssertNotNil(real.processTable(["-eo", "pid="], ProcessTable.budget),
                        "a seam wired to a closure answering nil would read as no session running, "
                            + "which is the laundering CLIStateLocationTests closes downstream")
        XCTAssertNotNil(real.processEnvironment(getpid(), nil).values,
                        "and this process can always read its own environment")
    }

    func testTheRealStatusIsTheCLIsOwn() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/SystemWorld.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        XCTAssertTrue(text.contains("cliStatus: { CLI.status() }"),
                      "asserted on the text rather than by calling it, because calling it runs "
                          + "claude auth status as a subprocess — the rest of this world is "
                          + "exercised for real just above")
    }
}
