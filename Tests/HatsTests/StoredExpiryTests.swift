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
        let store = AccountStore(osAccount: "expiry-test-\(UUID().uuidString.prefix(8))",
                                 keychain: FakeKeychain().world())
        let address = "\(UUID().uuidString.prefix(8))@b.com"
        let hat = try store.add(email: address, browser: .chrome(.stable, "Profile 1"))

        return (store, hat.id)
    }

    func testACredentialCarryingAnExpiryRecordsIt() throws {
        let (store, id) = try self.store()

        store.noteStored(id, payload: payload(refreshExpires: expiry), identity: nil)

        XCTAssertEqual(store.accounts.first { $0.id == id }?.refreshExpiresAt, expiry)
    }

    func testACredentialWithoutAnExpiryErasesTheOneLeftByThePreviousLogin() throws {
        let (store, id) = try self.store()
        let past = Date().addingTimeInterval(-3600)
        store.noteStored(id, payload: payload(refreshExpires: past), identity: nil)

        store.noteStored(id, payload: payload(refreshExpires: nil), identity: nil)

        let hat = try XCTUnwrap(store.accounts.first { $0.id == id })
        XCTAssertNil(hat.refreshExpiresAt,
                     "the date belongs to the credential it came with. Claude Code 2.1.300 writes "
                         + "no refreshTokenExpiresAt, and keeping the old date marked a login made "
                         + "two hours earlier as expired — measured live on 2026-10-15")
        XCTAssertFalse(hat.isExpired)
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
