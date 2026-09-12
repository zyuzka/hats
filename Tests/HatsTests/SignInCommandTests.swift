import XCTest
@testable import Hats

final class SignInCommandTests: XCTestCase {
    func testTheAccountBeingSignedInIsPassedAsTheEmailHint() throws {
        let command = try SignInCommand.of(executable: "/bin/claude", email: "a@b.com", browser: nil)

        XCTAssertEqual(command.executable, "/bin/claude")
        XCTAssertEqual(command.arguments, ["auth", "login", "--email", "a@b.com"])
    }

    func testNoAddressMeansNoHintRatherThanAnEmptyOne() throws {
        let command = try SignInCommand.of(executable: "/bin/claude", email: "", browser: nil)

        XCTAssertEqual(command.arguments, ["auth", "login"],
                       "an empty --email would pre-populate the login page with nothing and read "
                           + "as a defect on screen")
    }

    func testTheBrowserWrapperReachesTheCommandAsAPathRatherThanAShellWord() throws {
        let command = try SignInCommand.of(
            executable: "/bin/claude",
            email: "a@b.com",
            browser: .chromeProfile("Profile 1")
        )
        let browser = try XCTUnwrap(command.environment["BROWSER"])

        XCTAssertFalse(browser.hasPrefix("'"),
                       "the shell used to split that assignment; a Process does not, so a quoted "
                           + "path would be handed to the CLI with the quotes in it")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: browser))
    }

    func testTheCommandInheritsTheEnvironmentItRunsIn() throws {
        let command = try SignInCommand.of(executable: "/bin/claude", email: nil, browser: nil)

        XCTAssertEqual(command.environment["HOME"], ProcessInfo.processInfo.environment["HOME"])
        XCTAssertNil(command.environment["BROWSER"],
                     "no browser chosen means the CLI keeps whatever the system does, and an "
                         + "invented value would send the login to the wrong profile")
    }

    func testWithoutTheCLIThereIsNothingToRunAndItSaysSo() {
        XCTAssertThrowsError(try SignInCommand.of(executable: nil, email: "a@b.com", browser: nil)) {
            guard case SwitchError.cliNotFound = $0 else {
                return XCTFail("the app used to hand the line to a shell, which would search PATH; "
                    + "a Process launched from a bundle has no such PATH and must say what is "
                    + "missing instead of failing to spawn — got \($0)")
            }
        }
    }
}
