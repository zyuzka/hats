import XCTest
@testable import Hats

final class AccountStoreOfflineTests: XCTestCase {
    private let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Hats")

    func testTheStoreAsksWhoseTokenItIsThroughTheFetchItWasGiven() {
        var asked: [String] = []
        let fetched = expectation(description: "the store asked through the fetch it was given")
        let store = AccountStore(
            osAccount: "offline-test",
            keychain: FakeKeychain().world(),
            fetchingTokenIdentity: { token in
                asked.append(token)
                fetched.fulfill()
                return OfflineProfile.fetch(token)
            }
        )
        let live = Data(#"{"claudeAiOauth":{"accessToken":"live-token"}}"#.utf8)

        store.askWhoseTokenIsInTheSlot(expecting: "someone@example.co", credential: live, at: "test")
        wait(for: [fetched], timeout: 1.0)

        XCTAssertEqual(
            asked,
            [
                "live-token",
            ]
        )
    }

    func testTheAppBuildsItsStoreOnlyThroughTheLiveFactory() throws {
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)

        XCTAssertTrue(main.contains("AccountStore.createLive()"))
        XCTAssertFalse(
            main.contains("AccountStore("),
            "a store built directly in the app has to choose a fetch, and only the factory chooses the real one"
        )
    }

    func testTheLiveFactoryAsksTheProfileServer() throws {
        let store = try String(contentsOf: sources.appendingPathComponent("AccountStore.swift"), encoding: .utf8)
        let factory = try XCTUnwrap(store.range(of: "func createLive("))
        let end = store[factory.upperBound...].range(of: "\n\n")?.lowerBound ?? store.endIndex

        XCTAssertTrue(
            store[factory.upperBound..<end].contains("ProfileFetcher.fetch"),
            "the app's store is the one store that may reach the network"
        )
    }
}
