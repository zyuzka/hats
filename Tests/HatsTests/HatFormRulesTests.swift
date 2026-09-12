import XCTest
@testable import Hats

final class HatFormRulesTests: XCTestCase {
    func testAHatNeedsAnAddressAndABrowserOfItsOwn() {
        XCTAssertTrue(HatFormRules.canAdd(email: "a@b.com", browser: .chrome(.stable, "Profile 1")))
        XCTAssertFalse(HatFormRules.canAdd(email: "", browser: .chrome(.stable, "Profile 1")))
        XCTAssertFalse(HatFormRules.canAdd(email: "   ", browser: .chrome(.stable, "Profile 1")),
                       "spaces are not an address, and the old dialog accepted them as far as the "
                           + "button and only then returned nothing")
        XCTAssertFalse(HatFormRules.canAdd(email: "a@b.com", browser: nil))
    }

    func testASystemDefaultBrowserIsNotABrowserOfItsOwn() {
        XCTAssertFalse(HatFormRules.canAdd(email: "a@b.com", browser: .systemDefault),
                       "a login that goes to the default browser lands in whichever account that "
                           + "browser remembers, which is the whole thing this app exists to stop")
    }
}
