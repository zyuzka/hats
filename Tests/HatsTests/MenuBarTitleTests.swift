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
