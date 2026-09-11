import XCTest
@testable import Hats

final class RenewalRecordTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func hat() -> Account {
        var hat = Account(id: "a", email: "filip@company.com", browser: nil)
        hat.accessExpiresAt = now.addingTimeInterval(-60)
        hat.refreshExpiresAt = now.addingTimeInterval(28 * 24 * 3600)

        return hat
    }

    private func login(refreshExpiresAt: Date?) -> RenewedLogin {
        RenewedLogin(accessToken: "a-2",
                     refreshToken: "r-2",
                     expiresAt: now.addingTimeInterval(28800),
                     refreshExpiresAt: refreshExpiresAt,
                     scopes: [],
                     account: nil)
    }

    func testARenewalMovesTheAccessExpiryTheRowIsBuiltFrom() {
        let renewed = hat().afterARenewal(login(refreshExpiresAt: nil))

        XCTAssertEqual(renewed.accessExpiresAt, now.addingTimeInterval(28800),
                       "the popover line is built from soonestParkedAccessExpiry and says \"at its "
                           + "next token renewal, by about …\" — left stale it reads \"due now or "
                           + "overdue\" right after a renewal that did happen")
    }

    func testAnAnswerWithoutARefreshExpiryKeepsTheStoredOne() {
        let before = hat()
        let renewed = before.afterARenewal(login(refreshExpiresAt: nil))

        XCTAssertEqual(renewed.refreshExpiresAt, before.refreshExpiresAt,
                       "refresh_token_expires_in is optional in the answer and the CLI's own store "
                           + "keeps the previous value when it is absent; nilling it here would "
                           + "make isExpired and needsLoginSoon read a login as unbounded")
    }

    func testAnAnswerCarryingARefreshExpiryReplacesIt() {
        let moved = now.addingTimeInterval(30 * 24 * 3600)
        let renewed = hat().afterARenewal(login(refreshExpiresAt: moved))

        XCTAssertEqual(renewed.refreshExpiresAt, moved,
                       "a rotated refresh token brings its own lifetime, and keeping the old one "
                           + "would put the login's death earlier than it is")
    }

    func testARenewalTouchesNothingElseOnTheHat() {
        var before = hat()
        before.authRefusedAt = now
        before.lastLoginAt = now.addingTimeInterval(-3600)
        let renewed = before.afterARenewal(login(refreshExpiresAt: nil))

        XCTAssertEqual(renewed.authRefusedAt, before.authRefusedAt,
                       "a mint proves the refresh token is good and says nothing about the access "
                           + "token a poll was refused on; AuthObservation owns that field")
        XCTAssertEqual(renewed.lastLoginAt, before.lastLoginAt,
                       "nobody logged in — a renewal is the app doing what the CLI would have done")
        XCTAssertEqual(renewed.id, before.id)
        XCTAssertEqual(renewed.email, before.email)
    }

    func testARenewalNamingAnotherAccountIsNotRecordedOnThisHat() {
        let hat = self.hat()

        XCTAssertTrue(hat.allowsARenewalFor(nil), "the answer need not name an account at all")
        XCTAssertTrue(hat.allowsARenewalFor("FILIP@Company.com"),
                      "the comparison is the one the rest of the app uses, so case and padding "
                          + "must not make a hat disown its own renewal")
        XCTAssertFalse(hat.allowsARenewalFor("someone-else@company.com"),
                       "an answer that mints for another account would otherwise move this hat's "
                           + "stored expiry, and the usage read on that token is reported under "
                           + "this hat's name")
    }

    func testAMintForAnotherAccountLeavesEveryStoredDateAlone() {
        let before = hat()
        let stranger = RenewedLogin(accessToken: "a-2", refreshToken: "r-2",
                                    expiresAt: now.addingTimeInterval(28800),
                                    refreshExpiresAt: nil, scopes: [],
                                    account: "someone-else@company.com")

        XCTAssertFalse(before.allowsARenewalFor(stranger.account))
        XCTAssertEqual(before.afterARenewal(stranger).accessExpiresAt,
                       now.addingTimeInterval(28800),
                       "afterARenewal itself does not judge — the refusal belongs to the caller, "
                           + "and this check pins which of the two owns it")
    }
}
