import XCTest
@testable import Hats

final class SessionHandoffFlowTests: XCTestCase {
    private let list = FakePluginWorld.claude(SessionHandoffSteps.listArguments)
    private let marketplaces = FakePluginWorld.claude(SessionHandoffSteps.marketplaceArguments)
    private let install = FakePluginWorld.claude([
        "plugin",
        "install",
        "hats",
        "--marketplace",
        "zyuzka/hats",
        "--scope",
        "user",
        "--json",
    ])
    private let uninstall = FakePluginWorld.claude(SessionHandoffSteps.removeArguments)

    private var answers: [Bool] = []
    private var asked: [HatPrompt] = []
    private var informed: [String] = []
    private var shown = 0

    private func createFlow(_ fake: FakePluginWorld) -> SessionHandoffFlow {
        SessionHandoffFlow(
            perform: { work in work(fake.world()) },
            onMain: { $0() },
            ask: { [unowned self] prompt in
                asked.append(prompt)
                return answers.isEmpty ? false : answers.removeFirst()
            },
            inform: { [unowned self] title, _ in informed.append(title) },
            show: { [unowned self] in shown += 1 }
        )
    }

    private func installedFake() -> FakePluginWorld {
        let fake = FakePluginWorld()
        fake.answer(list, PluginCLISamples.listUserFromFolder)
        fake.answer(marketplaces, PluginCLISamples.marketplacesFolder)
        fake.answer(uninstall, PluginCLISamples.uninstallDone)

        return fake
    }

    func testOpeningTheSettingsReadsTheState() {
        let fake = installedFake()
        let flow = createFlow(fake)

        flow.refresh()

        XCTAssertTrue(fake.commands.contains(list))
        XCTAssertEqual(flow.row, SessionHandoffRow(
            face: .installed(version: "0.1.0", folder: "/market", isEnabled: true, elsewhere: []),
            isBusy: false
        ))
        XCTAssertGreaterThanOrEqual(shown, 2, "busy first, then the state that was read")
    }

    func testCancelInTheInstallWindowChangesNothing() {
        let fake = FakePluginWorld()
        let flow = createFlow(fake)
        answers = [false]

        flow.install()

        XCTAssertEqual(asked.map(\.title), ["Install the session handoff plugin?"])
        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertEqual(informed, [])
        XCTAssertFalse(flow.row.isBusy)
    }

    func testInstallInTheWindowInstallsExactlyOnce() {
        let fake = FakePluginWorld()
        fake.answer(install, PluginCLISamples.installFromFolder)
        fake.queue(list, [
            PluginCLISamples.listEmpty.outcome,
            PluginCLISamples.listEmpty.outcome,
            PluginCLISamples.listUserFromFolder.outcome,
        ])
        fake.queue(marketplaces, [
            PluginCLISamples.marketplacesEmpty.outcome,
            PluginCLISamples.marketplacesEmpty.outcome,
            PluginCLISamples.marketplacesFolder.outcome,
        ])
        let flow = createFlow(fake)
        answers = [true]

        flow.install()

        XCTAssertEqual(fake.changingRuns.map { FakePluginWorld.key($0.executable, $0.arguments) }, [install])
        XCTAssertEqual(informed, [])
        XCTAssertTrue(flow.row.face.canRemove)
        XCTAssertFalse(flow.row.isBusy)
    }

    func testARefusedInstallSaysWhyWithoutAsking() {
        let fake = FakePluginWorld()
        fake.installed = []
        let flow = createFlow(fake)
        answers = [true]

        flow.install()

        XCTAssertEqual(asked, [])
        XCTAssertEqual(informed, [SessionHandoffFlow.notInstalledTitle])
        XCTAssertEqual(fake.changingRuns, [])
    }

    func testCancelInTheRemoveWindowChangesNothing() {
        let fake = installedFake()
        let flow = createFlow(fake)
        flow.refresh()
        answers = [false]

        flow.remove()

        XCTAssertEqual(asked.map(\.title), ["Remove the session handoff plugin?"])
        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertFalse(flow.row.isBusy)
    }

    func testRemoveInTheWindowRemovesExactlyOnce() {
        let fake = installedFake()
        let flow = createFlow(fake)
        flow.refresh()
        fake.queue(list, [
            PluginCLISamples.listUserFromFolder.outcome,
            PluginCLISamples.listEmpty.outcome,
        ])
        answers = [true]

        flow.remove()

        XCTAssertEqual(fake.changingRuns.map { FakePluginWorld.key($0.executable, $0.arguments) }, [uninstall])
        XCTAssertEqual(flow.row.face, .notInstalled(elsewhere: []))
        XCTAssertEqual(informed, [])
    }

    func testRemoveIsNotAskedWhenNothingOfOursIsInstalled() {
        let fake = FakePluginWorld()
        let flow = createFlow(fake)
        flow.refresh()
        answers = [true]

        flow.remove()

        XCTAssertEqual(asked, [])
        XCTAssertEqual(fake.changingRuns, [])
    }
}
