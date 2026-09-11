import XCTest
@testable import Hats

final class ChromeProfilesTests: XCTestCase {
    private func localState(_ cache: String) -> Data {
        let json = #"{"profile":{"info_cache":{"# + cache + #"},"last_used":"Profile 6"}}"#
        return Data(json.utf8)
    }

    func testAProfileIsNamedTheWayChromeShowsIt() {
        let names = ChromeProfiles.names(localState: localState(#"""
        "Profile 6": {"name": "example.com", "gaia_name": "Filip", "user_name": "filip@example.com"},
        "Default": {"name": "Person 1", "is_using_default_name": true},
        "Profile 2": {"gaia_name": "Dana", "user_name": "dana@example.com"},
        "Profile 3": {"user_name": "only@example.com"},
        "Profile 4": {"name": "  ", "user_name": ""}
        """#))
        XCTAssertEqual(names["Profile 6"], "example.com (filip@example.com)")
        XCTAssertEqual(names["Default"], "Person 1", "a name Chrome made up is still the name Chrome shows")
        XCTAssertEqual(names["Profile 2"], "Dana (dana@example.com)", "the account name stands in for a missing local one")
        XCTAssertEqual(names["Profile 3"], "only@example.com")
        XCTAssertNil(names["Profile 4"], "blank fields name nothing, so the directory stays the label")
    }

    func testANameThatAlreadyCarriesTheAddressIsNotRepeated() {
        let names = ChromeProfiles.names(localState: localState(#"""
        "Profile 1": {"name": "work — dana@example.com", "user_name": "Dana@Example.com"}
        """#))
        XCTAssertEqual(names["Profile 1"], "work — dana@example.com")
    }

    func testAnUnreadableOrForeignFileNamesNothing() {
        XCTAssertEqual(ChromeProfiles.names(localState: Data("not json".utf8)), [:])
        XCTAssertEqual(ChromeProfiles.names(localState: Data(#"{"profile":{}}"#.utf8)), [:])
        XCTAssertEqual(ChromeProfiles.names(localState: Data(#"{"profile":{"info_cache":{"Profile 1":"x"}}}"#.utf8)), [:])
    }

    func testTheLabelFallsBackToTheDirectoryWhenChromeHasNoName() {
        let names = ["Profile 6": "example.com (filip@example.com)"]
        XCTAssertEqual(BrowserChoice.chromeProfile("Profile 6").label(chromeNames: names),
                       "Chrome — example.com (filip@example.com)")
        XCTAssertEqual(BrowserChoice.chromeProfile("Profile 7").label(chromeNames: names), "Chrome — Profile 7")
        XCTAssertEqual(BrowserChoice.chromeProfile("Profile 6").label, "Chrome — Profile 6")
        XCTAssertEqual(BrowserChoice.firefox.label(chromeNames: names), "Firefox")
    }
}
