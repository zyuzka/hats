import XCTest
@testable import Hats

final class MenuBarTitleTests: XCTestCase {
    private func snapshot(showingName: Bool, wearing: Bool) -> HatsSnapshot {
        var snapshot = HatsSnapshot()
        var settings = AppSettings()
        settings.showsHatNameInTheMenuBar = showingName
        snapshot.settings = settings
        let hat = Account(id: "a", email: "someone@example.com", name: "Client work")
        snapshot.rows = [HatRowState(hat: hat, isWearing: wearing, usage: nil, usageTrouble: nil)]
        return snapshot
    }

    func testTheNameShowsByDefaultAndTheSettingIsTheOnlyThingThatHidesIt() {
        XCTAssertEqual(snapshot(showingName: true, wearing: true).menuBarTitle, " Client work")
        XCTAssertEqual(snapshot(showingName: false, wearing: true).menuBarTitle, "",
                       "the menu bar is on every shared screen and in every screenshot")
        XCTAssertEqual(snapshot(showingName: true, wearing: false).menuBarTitle, "",
                       "no hat on, nothing to name — as before the setting existed")
        XCTAssertEqual(snapshot(showingName: false, wearing: false).menuBarTitle, "")
    }

    func testAnUnrenamedHatWouldPutTheAddressInTheMenuBarWhichIsWhyTheSwitchExists() {
        var snapshot = HatsSnapshot()
        let unnamed = Account(id: "a", email: "someone@example.com")
        snapshot.rows = [HatRowState(hat: unnamed, isWearing: true, usage: nil, usageTrouble: nil)]
        XCTAssertEqual(snapshot.menuBarTitle, " someone@example.com",
                       "Account.title falls back to the address, so a fresh install broadcasts one")
    }

    func testTheHatIsStillAnnouncedWhenItsNameIsHiddenFromTheBar() {
        XCTAssertEqual(snapshot(showingName: true, wearing: true).menuBarAccessibilityLabel,
                       "Hats — wearing Client work")
        XCTAssertEqual(snapshot(showingName: false, wearing: true).menuBarAccessibilityLabel,
                       "Hats — wearing Client work",
                       "the mark is a template image with no text; hiding the title would otherwise "
                           + "remove the only statement of which hat is on for a VoiceOver user")
        XCTAssertEqual(snapshot(showingName: false, wearing: false).menuBarAccessibilityLabel,
                       "Hats — no hat on")
    }

    private func blindSnapshot(isOn: Bool, wearing: Bool = true) -> HatsSnapshot {
        var snapshot = self.snapshot(showingName: true, wearing: wearing)
        snapshot.settings.autoSwitch.isOn = isOn
        snapshot.usageOfTheWornHatCannotBeRead = true
        return snapshot
    }

    func testAUsageThatCannotBeReadIsAnnouncedAndNotOnlyDrawn() {
        XCTAssertEqual(blindSnapshot(isOn: true).menuBarAccessibilityLabel,
                       "Hats — wearing Client work, usage can't be read",
                       "a sighted person sees the hole punched in the cursor; without this line a "
                           + "VoiceOver user is told only which hat is on, which is the one thing "
                           + "that has not changed")
        XCTAssertEqual(blindSnapshot(isOn: false).menuBarAccessibilityLabel,
                       "Hats — wearing Client work",
                       "with auto-switching off nothing is going to happen, so there is nothing to "
                           + "announce")
        XCTAssertEqual(blindSnapshot(isOn: true, wearing: false).menuBarAccessibilityLabel,
                       "Hats — no hat on")
    }

    func testTheDotAndTheSpokenLabelReadTheSameValue() {
        XCTAssertTrue(blindSnapshot(isOn: true).showsTheUsageCannotBeRead)
        XCTAssertFalse(blindSnapshot(isOn: false).showsTheUsageCannotBeRead,
                       "the guard on the switch being on lives here, where a test can ask it - in "
                           + "markState it was an expression inside a private method of a class no "
                           + "test in this project builds, so removing it would have lit the dot "
                           + "for somebody who never turned auto-switching on and nothing would "
                           + "have noticed")
        XCTAssertFalse(snapshot(showingName: true, wearing: true).showsTheUsageCannotBeRead)
    }

    func testASettingsFileWrittenBeforeThisFeatureKeepsShowingTheName() throws {
        let older = Data(#"{"gatewayPort":8787,"isGatewayEnabled":true}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: older)
        XCTAssertTrue(decoded.showsHatNameInTheMenuBar,
                      "an absent key must not change what the menu bar shows")
    }

    func testTheChoiceSurvivesASaveAndLoad() throws {
        var settings = AppSettings()
        settings.showsHatNameInTheMenuBar = false
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(round.showsHatNameInTheMenuBar)
    }
}
