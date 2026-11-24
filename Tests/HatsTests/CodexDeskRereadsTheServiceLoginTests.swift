import XCTest
@testable import Hats

final class CodexDeskRereadsTheServiceLoginTests: XCTestCase {
    private var home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let work = CodexFixture.ticket("hat-work", CodexFixture.work)
    private let personal = CodexFixture.ticket("hat-personal", CodexFixture.personal)
    private var rereads: [String] = []

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
        super.tearDown()
    }

    private func makeDesk() -> CodexDesk {
        var world = server.world(home: home, keychain: keychain)
        world.rereadServiceLogin = { [unowned self] hat, _ in rereads.append(hat) }
        return CodexDesk(world: world)
    }

    func testWearingAnotherHatAsksTheServiceToRereadTheLogin() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "w-1").write(to: home.auth)
        keychain.contents[Slot.codexParked(work.id)] = CodexFixture.login(CodexFixture.work, refresh: "w-1")
        keychain.contents[Slot.codexParked(personal.id)] = CodexFixture.login(CodexFixture.personal, refresh: "p-1")

        _ = try makeDesk().wearNow(personal, among: [work, personal])

        XCTAssertEqual(rereads, [personal.id])
    }

    func testWearingTheHatAlreadyWornAsksNothing() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "w-1").write(to: home.auth)
        keychain.contents[Slot.codexParked(work.id)] = CodexFixture.login(CodexFixture.work, refresh: "w-1")

        let worn = try makeDesk().wearNow(work, among: [work, personal])

        XCTAssertEqual(worn, .alreadyWorn(work.id))
        XCTAssertEqual(rereads, [])
    }

    func testSigningTheWornHatInAgainAsksTheServiceToRereadTheLogin() throws {
        try CodexFixture.login(CodexFixture.work, refresh: "w-1").write(to: home.auth)

        _ = try makeDesk().replaceLive(with: CodexFixture.login(CodexFixture.work, refresh: "w-2"), for: work)

        XCTAssertEqual(rereads, [work.id])
    }

    func testALoginWornByAnotherAccountIsNotReplacedAndAsksNothing() throws {
        try CodexFixture.login(CodexFixture.personal, refresh: "p-1").write(to: home.auth)

        _ = try makeDesk().replaceLive(with: CodexFixture.login(CodexFixture.work, refresh: "w-2"), for: work)

        XCTAssertEqual(rereads, [])
    }

    func testRenewingTheWornLoginAsksTheServiceToRereadIt() throws {
        let due = CodexFixture.login(
            CodexFixture.work,
            refresh: "w-1",
            expiresAt: CodexFixture.now.addingTimeInterval(3600)
        )
        try due.write(to: home.auth)
        keychain.contents[Slot.codexParked(work.id)] = due
        let desk = makeDesk()
        desk.noteWornHere(work.id)
        server.renewed(["access_token": "work-access-2", "refresh_token": "w-2"])

        guard case .fresh = desk.renewWornNow(work) else { return XCTFail("the worn login is renewed") }

        XCTAssertEqual(rereads, [work.id])
    }
}
