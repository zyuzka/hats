import XCTest
@testable import Hats

final class AbsurdExpiryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAnExpiryTooFarToCountIsShownInsteadOfTrapping() throws {
        let block = OAuthBlock(expiresAt: 1e300, refreshTokenExpiresAt: 1e300)
        let expires = try XCTUnwrap(block.expires)
        var hat = Account(id: "absurd", email: "absurd@x.co", browser: nil)
        hat.refreshExpiresAt = try XCTUnwrap(block.refreshExpires)

        let remaining = HatsCopy.humanise(expires.timeIntervalSince(now))

        XCTAssertTrue(remaining.hasSuffix("h") && remaining.contains("d "),
                      "Int(seconds) of 1e297 trapped and took the gateway down with the app; got \(remaining)")
        XCTAssertNotNil(HatsCopy.loginValidity(for: hat, now: now))
        XCTAssertTrue(SessionHorizon.minutes(expires.timeIntervalSince(now)).hasPrefix("in "))
        XCTAssertTrue(SessionHorizon.minutes(.infinity).hasPrefix("in "))
        XCTAssertEqual(HatsCopy.humanise(.nan), "expired")
    }

    func testOrdinaryExpiriesAreCountedAsBefore() {
        XCTAssertEqual(HatsCopy.humanise(90_061), "1d 1h")
        XCTAssertEqual(HatsCopy.humanise(3_661), "1h 1m")
        XCTAssertEqual(SessionHorizon.minutes(3_660), "in 1 h 1 min")
        XCTAssertEqual(SessionHorizon.minutes(59.9), "under a minute")
    }
}
