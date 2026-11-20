import XCTest
@testable import Hats

final class CodexQueueTests: XCTestCase {
    private let home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let personal = CodexFixture.ticket("hat-personal", CodexFixture.personal)

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
    }

    func testAClickWhileTheRenewalIsInFlightWaitsAndPutsOnTheNewLogin() throws {
        let queue = DispatchQueue(label: "test.codex.desk")
        let requestSent = DispatchSemaphore(value: 0)
        let answerMayGo = DispatchSemaphore(value: 0)
        server.duringSend = {
            requestSent.signal()
            answerMayGo.wait()
        }
        var world = server.world(home: home, keychain: keychain)
        world.run = { queue.async(execute: $0) }
        let desk = CodexDesk(world: world)
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(
            CodexFixture.personal, refresh: "p-1", expiresAt: CodexFixture.now.addingTimeInterval(3600))
        server.renewed(["access_token": "p-access-2", "refresh_token": "p-2"])
        let renewed = expectation(description: "renewed")
        let worn = DispatchSemaphore(value: 0)

        desk.renew([personal]) { _ in renewed.fulfill() }
        XCTAssertEqual(requestSent.wait(timeout: .now() + 5), .success)
        desk.wear(personal, among: [personal]) { _, _ in worn.signal() }

        XCTAssertEqual(worn.wait(timeout: .now() + 0.3), .timedOut,
                       "the click waits while the answer for the same hat is on its way")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.auth.path))
        answerMayGo.signal()
        wait(for: [renewed], timeout: 5)
        XCTAssertEqual(worn.wait(timeout: .now() + 5), .success)

        XCTAssertEqual(CodexFixture.refreshToken(in: try Data(contentsOf: home.auth)), "p-2")
        XCTAssertEqual(server.sentRefreshTokens, ["p-1"])
    }
}
