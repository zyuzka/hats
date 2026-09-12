import XCTest
@testable import Hats

final class StoredExpiryTests: XCTestCase {
    private let expiry = Date(timeIntervalSince1970: 1_800_000_000)

    private func payload(refreshExpires: Date?) -> CredentialPayload {
        var oauth: [String: Any] = ["accessToken": "t", "expiresAt": 1_700_000_000_000.0]
        if let refreshExpires {
            oauth["refreshTokenExpiresAt"] = refreshExpires.timeIntervalSince1970 * 1000
        }
        let raw = try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])

        return CredentialPayload(raw: raw)
    }

    private func store() throws -> (AccountStore, String) {
        let store = AccountStore(osAccount: "expiry-test-\(UUID().uuidString.prefix(8))")
        let address = "\(UUID().uuidString.prefix(8))@b.com"
        let hat = try store.add(email: address, browser: .chrome(.stable, "Profile 1"))

        return (store, hat.id)
    }

    func testACredentialCarryingAnExpiryRecordsIt() throws {
        let (store, id) = try self.store()

        store.noteStored(id, payload: payload(refreshExpires: expiry), identity: nil)

        XCTAssertEqual(store.accounts.first { $0.id == id }?.refreshExpiresAt, expiry)
    }

    func testAFreshLoginDoesNotEraseAnExpiryItWasNotTold() throws {
        let (store, id) = try self.store()
        store.noteStored(id, payload: payload(refreshExpires: expiry), identity: nil)

        store.noteStored(id, payload: payload(refreshExpires: nil), identity: nil)

        XCTAssertEqual(store.accounts.first { $0.id == id }?.refreshExpiresAt, expiry,
                       "a credential written by `claude auth login` carries no "
                           + "refreshTokenExpiresAt, and overwriting with nothing leaves the hat "
                           + "unable to say the login expired or is about to — both read the field "
                           + "and return false when it is absent. Renewal already keeps it")
    }

    func testWithoutAnyExpiryTheHatCannotWarnAtAll() {
        var hat = Account(id: "a", email: "a@b.com", browser: nil)
        hat.hasStoredCredentials = true
        hat.refreshExpiresAt = nil

        XCTAssertFalse(hat.needsLoginSoon)
        XCTAssertFalse(hat.isExpired(at: Date(timeIntervalSince1970: 9_999_999_999)),
                       "this is what the erasure costs: a login a year past its end reads as fine")
    }
}
