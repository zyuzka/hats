import XCTest
@testable import Hats

final class RememberedConfigurationWorldTests: XCTestCase {
    override func setUp() {
        CLIState.forgetTheCLIConfiguration()
    }

    override func tearDown() {
        CLIState.forgetTheCLIConfiguration()
    }

    func testTheRememberedConfigurationIsReadFromTheWorldItIsGiven() throws {
        let system = FakeSystem(home: "/fake-home")
        system.variables = [CLIState.configDirVariable: "/fake-config"]

        let configuration = try CLIState.configurationRemembered(world: system.world())

        XCTAssertEqual(configuration.variables, [CLIState.configDirVariable: "/fake-config"],
                       "the variables come from the world's own environment, not from this process")
        XCTAssertEqual(configuration.home, "/fake-home")
        XCTAssertEqual(configuration.source, .ourOwn)
        XCTAssertGreaterThan(system.homeAsked, 0)
    }

    func testTheSweepOfTheRememberedConfigurationGoesThroughTheWorld() throws {
        let system = FakeSystem(home: "/fake-home")
        system.table = { _ in nil }

        guard isTheSessionMemoryStale() else {
            return XCTFail("the shared one-second session memory stayed fresh for 1.5 s, so the sweep "
                               + "this test is about would not run")
        }

        XCTAssertThrowsError(try CLIState.configurationRemembered(world: system.world())) {
            guard case .liveSessionsUnreadable = $0 as? CLIStateError else {
                return XCTFail("a process table the world cannot read is an unreadable sweep, not an empty one: \($0)")
            }
        }
        XCTAssertFalse(system.processTables.isEmpty, "the process table was asked of the world")
        XCTAssertEqual(Set(system.budgets), [SessionDiscovery.readerBudget],
                       "the remembered sweep serves readers, so it keeps the readers' budget")
    }

    func testTheUsageWorldReadsAndWritesThroughTheKeychainItIsGiven() throws {
        let slot = Slot.parked("usage-world")
        let blob = credential(expiresAt: 1_800_000_000_000)
        let keychain = FakeKeychain([slot: blob])
        let world = UsageWorld.real(keychain: keychain.world())

        XCTAssertEqual(try world.read(slot), blob)
        try world.write(Slot.parked("usage-world-2"), blob)

        XCTAssertEqual(keychain.reads, [slot])
        XCTAssertEqual(keychain.contents[Slot.parked("usage-world-2")], blob,
                       "the poll's keychain is the store's keychain, not a second declaration of it")
    }

    private func isTheSessionMemoryStale() -> Bool {
        let deadline = Date().addingTimeInterval(1.5)
        while RecentSessions.shared.value(within: RecentSessions.window) != nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return RecentSessions.shared.value(within: RecentSessions.window) == nil
    }
}
