import XCTest
@testable import Hats

final class KeychainPrintedValueTests: XCTestCase {
    func testAOneLineValueIsReadAsPrinted() {
        let printed = #"{"claudeAiOauth":{"accessToken":"a"}}"#

        XCTAssertEqual(Keychain.storedValue(printed: printed), Data(printed.utf8))
    }

    func testAValueWithLineBreaksPrintedInHexIsReadBackAsItsBytes() {
        let stored = "{\n  \"auth_mode\": \"chatgpt\"\n}"
        let printed = Data(stored.utf8).map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(Keychain.storedValue(printed: printed), Data(stored.utf8))
    }

    func testHexDigitsThatDecodeToPrintableTextAreTheValueItself() {
        XCTAssertEqual(Keychain.storedValue(printed: "616263"), Data("616263".utf8))
    }

    func testAnOddLengthOfHexDigitsIsTheValueItself() {
        XCTAssertEqual(Keychain.storedValue(printed: "7b0"), Data("7b0".utf8))
    }
}
