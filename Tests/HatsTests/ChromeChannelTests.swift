import XCTest
@testable import Hats

final class ChromeChannelTests: XCTestCase {
    func testEachChannelKeepsItsOwnProfilesAndItsOwnApplication() {
        XCTAssertEqual(ChromeChannel.stable.application, "Google Chrome")
        XCTAssertEqual(ChromeChannel.canary.application, "Google Chrome Canary")
        XCTAssertTrue(ChromeChannel.canary.supportDirectory.path
            .hasSuffix("Library/Application Support/Google/Chrome Canary"))
        XCTAssertTrue(ChromeChannel.stable.supportDirectory.path
            .hasSuffix("Library/Application Support/Google/Chrome"))
    }

    func testOnlyTheOrdinaryChannelIsLeftUnnamedOnScreen() {
        XCTAssertEqual(ChromeChannel.stable.label, "Chrome")
        XCTAssertEqual(ChromeChannel.canary.label, "Chrome Canary",
                       "a person running three Claudes in three channels has to tell them apart")
    }
}

final class BrowserChoiceChannelTests: XCTestCase {
    func testAChoiceWrittenBeforeChannelsExistedStillMeansOrdinaryChrome() throws {
        let stored = Data(#"{"chromeProfile":{"_0":"Profile 6"}}"#.utf8)

        let choice = try JSONDecoder().decode(BrowserChoice.self, from: stored)

        XCTAssertEqual(choice, .chromeProfile("Profile 6"))
        XCTAssertEqual(choice.label(chromeNames: [:]), "Chrome — Profile 6",
                       "every hat on disk carries this shape, and a hat whose browser stops "
                           + "decoding cannot log in at all")
    }

    func testAChannelChoiceOpensThatChannelRatherThanChrome() throws {
        let canary = BrowserChoice.chrome(.canary, "Profile 1")

        let command = try XCTUnwrap(canary.openCommand)

        XCTAssertTrue(command.contains("'Google Chrome Canary'"), command)
        XCTAssertTrue(command.contains("--profile-directory='Profile 1'"), command)
    }

    func testTheSameProfileNameInTwoChannelsGetsTwoWrapperScripts() {
        let stable = BrowserChoice.chrome(.stable, "Profile 1")
        let canary = BrowserChoice.chrome(.canary, "Profile 1")

        XCTAssertNotEqual(stable.slug, canary.slug,
                          "both wrappers are written into browsers/<slug>.sh, so one slug for two "
                              + "channels means the second login silently opens the first one's "
                              + "browser")
    }

    func testTheChannelIsNamedOnTheRowNextToTheProfile() {
        let names = [ChromeProfiles.key(.canary, "Profile 1"): "Work"]

        XCTAssertEqual(BrowserChoice.chrome(.canary, "Profile 1").label(chromeNames: names),
                       "Chrome Canary — Work")
        XCTAssertEqual(BrowserChoice.chromeProfile("Profile 6").label(chromeNames: [:]),
                       "Chrome — Profile 6")
    }
}
