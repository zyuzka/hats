import XCTest
@testable import Hats

final class AccountStoreOfflineTests: XCTestCase {
    private let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Hats")

    func testTheFetchEveryTestStoreIsGivenAnswersWithoutTheNetwork() {
        let started = Date()

        let answer = OfflineProfile.fetch("live-token")

        XCTAssertEqual(answer, .unreachable)
        XCTAssertLessThan(
            Date().timeIntervalSince(started),
            0.05,
            "a request would take a round trip, up to the \(ProfileFetcher.budget)-second budget"
        )
    }

    func testTheAppBuildsItsStoreOnlyThroughTheLiveFactory() throws {
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)

        XCTAssertTrue(main.contains("AccountStore.createLive()"))
        XCTAssertEqual(
            main.components(separatedBy: "AccountStore").count - 1,
            1,
            "a store built directly in the app has to choose a fetch, and only the factory chooses the real one"
        )
    }

    func testTheLiveFactoryAsksTheProfileServer() throws {
        let store = try String(contentsOf: sources.appendingPathComponent("AccountStore.swift"), encoding: .utf8)
        let factory = try XCTUnwrap(store.range(of: "static func createLive() -> AccountStore {"))
        let body = try XCTUnwrap(store[factory.upperBound...].range(of: "\n    }\n"))

        XCTAssertTrue(
            store[factory.upperBound..<body.lowerBound].contains("ProfileFetcher.fetch(token: $0)"),
            "the app's store is the one store that may reach the network"
        )
    }
}
