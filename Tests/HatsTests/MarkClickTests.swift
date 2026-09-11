import XCTest
@testable import Hats

final class MarkClickTests: XCTestCase {
    func testAnOrdinaryClickOpensTheHatsRatherThanTheMenu() {
        XCTAssertEqual(MarkClick.of(isSecondaryButton: false, holdsControl: false), .popover,
                       "the common act is choosing a hat, so the plain click stays the popover")
    }

    func testTheSecondaryButtonOpensTheMenu() {
        XCTAssertEqual(MarkClick.of(isSecondaryButton: true, holdsControl: false), .menu,
                       "a right click on a menu-bar mark is where macOS users look for Quit")
    }

    func testControlHeldOpensTheMenuOnATrackpadWithNoSecondButton() {
        XCTAssertEqual(MarkClick.of(isSecondaryButton: false, holdsControl: true), .menu,
                       "control-click is the same gesture for anyone without a second button")
    }

    func testASecondaryClickWithControlHeldOpensTheMenu() {
        XCTAssertEqual(MarkClick.of(isSecondaryButton: true, holdsControl: true), .menu)
    }

    func testNoEventAtAllFallsBackToTheHats() {
        XCTAssertEqual(MarkClick.of(nil), .popover,
                       "an action fired without a current event must not pop a menu the user did not ask for")
    }
}
