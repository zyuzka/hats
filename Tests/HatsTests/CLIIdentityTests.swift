import XCTest
@testable import Hats

final class CLIIdentityTests: XCTestCase {
    private func identity(_ email: String?) -> CLIIdentity {
        CLIIdentity(oauthAccount: email.map { ["emailAddress": .string($0)] } ?? [:],
                    userID: nil)
    }

    func testAnIdentityMatchesItsOwnAddressHoweverItIsSpelled() {
        XCTAssertTrue(identity("a@b.co").matches("A@B.co "))
    }

    func testAnIdentityDoesNotMatchAnotherAddress() {
        XCTAssertFalse(identity("a@b.co").matches("someone@else.co"))
    }

    func testAnIdentityWithNoAddressMatchesNothing() {
        XCTAssertFalse(identity(nil).matches("a@b.co"))
        XCTAssertFalse(identity(nil).matches(""))
    }
}
