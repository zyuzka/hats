import XCTest
@testable import Hats

final class BrowserChoiceRememberedTests: XCTestCase {
    func testAnUnreadableChromeOffersTheRememberedProfilesAndTheDefaultOne() {
        let choices = BrowserChoice.chromeChoices(
            channel: .stable,
            readable: nil,
            remembered: [.chrome(.stable, "Profile 6"), .chrome(.canary, "Default"), .firefox]
        )

        XCTAssertEqual(choices, [.chrome(.stable, "Default"), .chrome(.stable, "Profile 6")])
    }

    func testAReadableChromeOffersWhatIsOnDiskOnly() {
        let choices = BrowserChoice.chromeChoices(
            channel: .stable,
            readable: ["Default"],
            remembered: [.chrome(.stable, "Profile 6")]
        )

        XCTAssertEqual(choices, [.chrome(.stable, "Default")])
    }

    func testAChannelThatIsNotThereOffersNothing() {
        let choices = BrowserChoice.chromeChoices(channel: .beta, readable: [], remembered: [.chrome(.beta, "Profile 2")])

        XCTAssertEqual(choices, [])
    }
}
