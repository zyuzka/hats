import UserNotifications
import XCTest
@testable import Hats

final class SessionHandoffNoticeTests: XCTestCase {
    private var told: [(title: String, body: String)] = []
    private var recorded: String?
    private var writes = 0

    private static let outdated = SessionHandoffFace.installed(
        version: "0.1.0",
        folder: nil,
        isEnabled: true,
        elsewhere: []
    )

    private func createNotice(own: String) -> SessionHandoffNotice {
        SessionHandoffNotice(
            own: own,
            notify: { [unowned self] title, body in told.append((title, body)) },
            findToldAbout: { [unowned self] in recorded },
            setToldAbout: { [unowned self] version in
                recorded = version
                writes += 1
            }
        )
    }

    private func source(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/\(name)")

        return try String(contentsOf: url, encoding: .utf8)
    }

    func testAnOutdatedSwitchedOnPluginIsToldAboutOnceAndRecorded() {
        let notice = createNotice(own: "0.2.0")

        notice.consider(Self.outdated)
        notice.consider(Self.outdated)

        XCTAssertEqual(told.map(\.title), ["Session handoff plugin 0.2.0"], "the same launch with the same own: once")
        XCTAssertEqual(told.first?.body, "A new version of the session handoff plugin is ready. Open Settings to update.")
        XCTAssertEqual(recorded, "0.2.0")
        XCTAssertEqual(writes, 1)
    }

    func testAnOwnVersionAboveTheRecordedOneIsTold() {
        recorded = "0.2.0"
        let notice = createNotice(own: "0.10.0")

        notice.consider(Self.outdated)

        XCTAssertEqual(told.map(\.title), ["Session handoff plugin 0.10.0"])
        XCTAssertEqual(recorded, "0.10.0")
    }

    func testAnOwnVersionAtOrBelowTheRecordedOneTellsNothing() {
        for already in ["0.2.0", "0.3.0"] {
            recorded = already
            let notice = createNotice(own: "0.2.0")

            notice.consider(Self.outdated)

            XCTAssertTrue(told.isEmpty, "recorded \(already)")
            XCTAssertEqual(recorded, already, "recorded \(already)")
        }
        XCTAssertEqual(writes, 0)
    }

    func testABrokenRecordedVersionCountsAsNotToldYet() {
        recorded = "not a version"
        let notice = createNotice(own: "0.2.0")

        notice.consider(Self.outdated)

        XCTAssertEqual(told.count, 1)
        XCTAssertEqual(recorded, "0.2.0")
    }

    func testNothingIsToldOrRecordedUnlessTheRowOffersAnUpdateOfASwitchedOnPlugin() {
        let silent: [(face: SessionHandoffFace, why: String)] = [
            (.unknown("The plugin list of Claude Code could not be read: timed out."), "the reading failed"),
            (.unread, "not read"),
            (.notInstalled(elsewhere: []), "not installed"),
            (.notOurs("another plugin under the name hats"), "not ours"),
            (.installed(version: "0.1.0", folder: "/market", isEnabled: true, elsewhere: []), "from a folder"),
            (.installed(version: "0.1.0", folder: nil, isEnabled: false, elsewhere: []), "switched off"),
            (.installed(version: "0.2.0", folder: nil, isEnabled: true, elsewhere: []), "fresh"),
            (.installed(version: nil, folder: nil, isEnabled: true, elsewhere: []), "no version"),
        ]
        let notice = createNotice(own: "0.2.0")

        for (face, why) in silent {
            notice.consider(face)

            XCTAssertTrue(told.isEmpty, why)
            XCTAssertNil(recorded, why)
        }
        notice.consider(Self.outdated)
        XCTAssertEqual(told.count, 1, "the same notice speaks for an outdated switched-on plugin")
    }

    func testTheLaunchReadsOnlyAndHandsTheStateOn() {
        let fake = FakePluginWorld()
        fake.answer(FakePluginWorld.claude(SessionHandoffSteps.listArguments), PluginCLISamples.listUserThroughGitHub010)
        fake.answer(
            FakePluginWorld.claude(SessionHandoffSteps.marketplaceArguments),
            PluginCLISamples.marketplacesThroughGitHub
        )
        let flow = SessionHandoffFlow(
            own: "0.2.0",
            perform: { $0(fake.world()) },
            onMain: { $0() },
            ask: { _ in true },
            inform: { _, _ in },
            show: {}
        )
        let notice = createNotice(own: "0.2.0")

        flow.refresh { notice.consider($0) }

        XCTAssertEqual(fake.commands, [
            FakePluginWorld.claude(["--version"]),
            FakePluginWorld.claude(SessionHandoffSteps.listArguments),
            FakePluginWorld.claude(SessionHandoffSteps.marketplaceArguments),
        ])
        XCTAssertEqual(fake.changingRuns, [])
        XCTAssertEqual(told.count, 1)
    }

    func testABusyRowSkipsTheLaunchReadingAndTellsNothing() {
        let fake = FakePluginWorld()
        var held: ((PluginWorld) -> Void)?
        let flow = SessionHandoffFlow(
            own: "0.2.0",
            perform: { held = $0 },
            onMain: { $0() },
            ask: { _ in true },
            inform: { _, _ in },
            show: {}
        )
        var handed = 0
        flow.refresh(then: nil)

        flow.refresh { _ in handed += 1 }

        XCTAssertNotNil(held)
        XCTAssertEqual(handed, 0)
        XCTAssertEqual(fake.runs, [])
        held?(fake.world())
        XCTAssertEqual(handed, 0, "the held work is the first reading's, which hands nothing on")
    }

    func testOnlyTheMarkedNotificationOpensSettingsAndShowsInTheForeground() {
        let marked: [AnyHashable: Any] = [Notifier.opensSettingsKey: true]

        XCTAssertTrue(Notifier.isOpeningSettings(marked))
        XCTAssertEqual(Notifier.getPresentation(marked), [.banner, .list])
        XCTAssertFalse(Notifier.isOpeningSettings([:]))
        XCTAssertEqual(Notifier.getPresentation([:]), [], "every other notification stays hidden in front, as before")
        XCTAssertFalse(Notifier.isOpeningSettings([Notifier.opensSettingsKey: "yes"]))
    }

    func testOnlyTheContentOfPostOpeningSettingsCarriesTheMark() {
        let marked = Notifier.createContentOpeningSettings(title: "Session handoff plugin 0.2.0", body: "ready")
        let plain = Notifier.createContent(title: "Hats 0.4.1 is out", body: "Install it from the update window.")

        XCTAssertTrue(Notifier.isOpeningSettings(marked.userInfo))
        XCTAssertFalse(Notifier.isOpeningSettings(plain.userInfo))
        XCTAssertEqual(marked.title, "Session handoff plugin 0.2.0")
        XCTAssertEqual(marked.body, "ready")
        XCTAssertEqual(plain.title, "Hats 0.4.1 is out")
    }

    func testOnlyAClickOnTheMarkedNotificationOpensSettings() {
        let marked: [AnyHashable: Any] = [Notifier.opensSettingsKey: true]

        XCTAssertTrue(Notifier.isClickOpeningSettings(UNNotificationDefaultActionIdentifier, marked))
        XCTAssertFalse(Notifier.isClickOpeningSettings(UNNotificationDismissActionIdentifier, marked), "closing it opens nothing")
        XCTAssertFalse(Notifier.isClickOpeningSettings(UNNotificationDefaultActionIdentifier, [:]), "a click on another one opens nothing")
    }

    func testTheAppTellsAtLaunchThroughTheMarkedNotificationAndOpensSettingsOnAClick() throws {
        let main = try source("main.swift")
        let handoff = try source("AppDelegate+SessionHandoff.swift")

        XCTAssertTrue(main.contains("Notifier.listen { [weak self] in self?.showSettings() }"))
        XCTAssertTrue(main.contains("own: SessionHandoffProvenance.bundledVersion"))
        XCTAssertTrue(main.contains("        offerThePluginUpdateOnce()\n"), "called at launch")
        XCTAssertTrue(handoff.contains("own: handoff.own"))
        XCTAssertTrue(handoff.contains("notify: { Notifier.postOpeningSettings(title: $0, body: $1) }"))
        XCTAssertTrue(handoff.contains("handoff.refresh { notice.consider($0) }"))
        XCTAssertTrue(handoff.contains("""
                    setToldAbout: { [weak self] version in
                        self?.settings.pluginVersionToldAbout = version
                        self?.saveSettings()
                    }
        """), "the told version is set and saved, or the next launch tells again")
    }
}
