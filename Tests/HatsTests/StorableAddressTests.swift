import XCTest
@testable import Hats

final class StorableAddressTests: XCTestCase {
    func testAnAddressOfNothingButWhitespaceIsNotStorable() {
        XCTAssertNil(Account.storableAddress(""))
        XCTAssertNil(Account.storableAddress("   "))
        XCTAssertNil(Account.storableAddress("\n\t "))
    }

    func testTheStoredAddressLosesItsSurroundingWhitespace() {
        XCTAssertEqual(Account.storableAddress("  a@b.co  "), "a@b.co")
    }

    func testTheStoredAddressKeepsItsOwnSpelling() {
        XCTAssertEqual(Account.storableAddress("A.User+ci@B.co"), "A.User+ci@B.co")
    }
}
