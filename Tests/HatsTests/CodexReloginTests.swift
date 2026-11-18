import XCTest
@testable import Hats

final class CodexReloginTests: XCTestCase {
    private var home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let work = CodexFixture.ticket("hat-work", CodexFixture.work)
    private let personal = CodexFixture.ticket("hat-personal", CodexFixture.personal)

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
    }

    private func relogin(_ data: Data, isWorn: Bool) -> (stored: Bool, result: Result<CodexWorn?, Error>)? {
        let desk = CodexDesk(world: server.world(home: home, keychain: keychain))
        var outcome: (Bool, Result<CodexWorn?, Error>)?
        desk.relogin(work, with: data, isWorn: isWorn, among: [work, personal]) { outcome = ($0, $1) }

        return outcome
    }

    func testSigningTheWornHatInAgainReplacesTheFileAndDoesNotParkTheOldOne() throws {
        let oldLive = CodexFixture.login(CodexFixture.work, refresh: "old-live")
        let fresh = CodexFixture.login(CodexFixture.work, refresh: "fresh")
        try oldLive.write(to: home.auth)
        keychain.contents[Slot.codexParked(work.id)] = CodexFixture.login(CodexFixture.work, refresh: "old-slot")

        let outcome = try XCTUnwrap(relogin(fresh, isWorn: true))

        XCTAssertTrue(outcome.stored)
        XCTAssertEqual(try outcome.result.get(), .worn(target: work.id, outgoing: nil, parked: nil))
        XCTAssertEqual(keychain.contents[Slot.codexParked(work.id)], fresh)
        XCTAssertEqual(try Data(contentsOf: home.auth), fresh)
        XCTAssertFalse(keychain.writes.contains { $0.data == oldLive }, "the old live file never went into a slot")
    }

    func testALiveFileThatCouldNotBeReplacedLeavesTheNewSlotAndTheOldFile() throws {
        let oldLive = CodexFixture.login(CodexFixture.work, refresh: "old-live")
        let fresh = CodexFixture.login(CodexFixture.work, refresh: "fresh")
        try oldLive.write(to: home.auth)
        home.rename = { _, _ in throw CodexError.writeFailed("disk full") }

        let outcome = try XCTUnwrap(relogin(fresh, isWorn: true))

        XCTAssertTrue(outcome.stored, "the slot is already new")
        XCTAssertThrowsError(try outcome.result.get())
        XCTAssertEqual(keychain.contents[Slot.codexParked(work.id)], fresh)
        XCTAssertEqual(try Data(contentsOf: home.auth), oldLive)
    }

    func testASlotThatDidNotTakeKeepsThePreviousLogin() throws {
        let previous = CodexFixture.login(CodexFixture.work, refresh: "previous")
        keychain.contents[Slot.codexParked(work.id)] = previous
        keychain.swallowsWrites = true

        let outcome = try XCTUnwrap(relogin(CodexFixture.login(CodexFixture.work, refresh: "fresh"), isWorn: false))

        XCTAssertFalse(outcome.stored)
        XCTAssertEqual(keychain.contents[Slot.codexParked(work.id)], previous)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.auth.path), "a parked hat's sign-in writes no file")
    }
}
