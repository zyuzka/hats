import XCTest
@testable import Hats

final class CodexPluginNoticeTests: XCTestCase {
    private var told: String?
    private var notified: [String] = []
    private var journaled: [String] = []

    private func createNotice(own: String) -> CodexPluginNotice {
        CodexPluginNotice(
            own: own,
            notify: { [unowned self] title, _ in notified.append(title) },
            findToldAbout: { [unowned self] in told },
            setToldAbout: { [unowned self] in told = $0 },
            journal: { [unowned self] operation, _ in journaled.append(operation) }
        )
    }

    private func source(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(path)

        return try String(contentsOf: url, encoding: .utf8)
    }

    func testAnOfferIsToldOncePerVersion() {
        let old = CodexPluginFace.installed(version: "0.1.0", isEnabled: true)

        createNotice(own: "0.2.0").consider(old)
        createNotice(own: "0.2.0").consider(old)
        XCTAssertEqual(notified, ["Codex plugin 0.2.0"])
        XCTAssertEqual(told, "0.2.0")
        XCTAssertEqual(journaled, ["codexPlugin.offered"])

        createNotice(own: "0.3.0").consider(old)
        XCTAssertEqual(notified, ["Codex plugin 0.2.0", "Codex plugin 0.3.0"])
    }

    func testNothingIsToldWithoutAnOffer() {
        let faces: [CodexPluginFace] = [
            .installed(version: "0.2.0", isEnabled: true),
            .installed(version: "0.1.0", isEnabled: false),
            .fromFolder(version: "0.1.0", folder: "/f", copy: .differs("x")),
            .notInstalled,
            .noCodex,
        ]
        for face in faces { createNotice(own: "0.2.0").consider(face) }

        XCTAssertEqual(notified, [])
        XCTAssertNil(told)
        XCTAssertEqual(journaled, [])
    }

    func testTheToldVersionSurvivesASave() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = AppSettings()
        settings.codexPluginVersionToldAbout = "0.2.0"

        try settings.save(to: url)

        XCTAssertEqual(AppSettings.loaded(from: url).codexPluginVersionToldAbout, "0.2.0")
        XCTAssertNil(AppSettings().codexPluginVersionToldAbout)
    }

    func testTheAppsNoticeKeepsAndSavesTheVersionItToldAbout() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = AppSettings()
        settings.isGatewayEnabled = false
        var saves = 0
        let notice = CodexPluginNotice.remembering(
            own: "0.2.0",
            notify: { [unowned self] title, _ in notified.append(title) },
            settings: { settings },
            keep: { settings = $0 },
            save: {
                saves += 1
                try? settings.save(to: url)
            }
        )

        notice.consider(.installed(version: "0.1.0", isEnabled: true))
        notice.consider(.installed(version: "0.1.0", isEnabled: true))

        XCTAssertEqual(notified, ["Codex plugin 0.2.0"], "the kept version stops the second notification")
        XCTAssertEqual(saves, 1, "saved once, after the version was kept")
        XCTAssertEqual(settings.codexPluginVersionToldAbout, "0.2.0")
        let saved = AppSettings.loaded(from: url)
        XCTAssertEqual(saved.codexPluginVersionToldAbout, "0.2.0", "told once even after Hats starts again")
        XCTAssertFalse(saved.isGatewayEnabled, "the rest of the settings is saved as it was")
    }

    func testTheRowOfTheFlowIsWhatTheSnapshotShows() {
        let fake = FakePluginWorld.withCodex()
        let flow = CodexPluginFlow(
            own: "0.1.0",
            perform: { work in work(fake.world()) },
            onMain: { $0() },
            ask: { _ in false },
            inform: { _, _ in },
            show: {},
            journal: { _, _ in }
        )
        flow.refresh(then: nil)
        var snapshot = HatsSnapshot()

        snapshot.showTheCodexPluginRow(of: flow)

        XCTAssertNotEqual(flow.row, CodexPluginRow(), "the read changed the row, so the check below means something")
        XCTAssertEqual(snapshot.codexPlugin, flow.row)
    }

    private func getText(of function: String, in text: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: function)).lowerBound
        let rest = text[start...]
        let end = rest.dropFirst().range(of: "\n    }\n")?.lowerBound ?? rest.endIndex

        return String(rest[..<end])
    }

    func testTheRedrawTakesTheRowAndTheLaunchNoticeRemembers() throws {
        let redraw = try getText(of: "func redraw()", in: source("Sources/Hats/AppDelegate+Redraw.swift"))
        let offer = try getText(
            of: "func offerTheCodexPluginUpdateOnce()",
            in: source("Sources/Hats/AppDelegate+CodexPlugin.swift")
        )

        XCTAssertTrue(redraw.contains("snapshot.showTheCodexPluginRow(of: codexPlugin)"))
        XCTAssertTrue(offer.contains("CodexPluginNotice.remembering("))
        XCTAssertTrue(offer.contains("keep: { [weak self] in self?.settings = $0 }"))
        XCTAssertTrue(offer.contains("save: { [weak self] in self?.saveSettings() }"))
        XCTAssertTrue(offer.contains("codexPlugin.refresh { notice.consider($0) }"))
    }

    func testTheBundledVersionIsTheVersionOfThePluginAndOfTheMarketplace() throws {
        let plugin = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(try source("codex-plugin/.codex-plugin/plugin.json").utf8)
        ) as? [String: Any])
        let market = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(try source(".agents/plugins/marketplace.json").utf8)
        ) as? [String: Any])
        let entries = try XCTUnwrap(market["plugins"] as? [[String: Any]])
        let ours = try XCTUnwrap(entries.first { $0["name"] as? String == CodexPluginProvenance.pluginName })

        XCTAssertEqual(plugin["version"] as? String, CodexPluginProvenance.bundledVersion)
        XCTAssertEqual(ours["version"] as? String, CodexPluginProvenance.bundledVersion)
        XCTAssertEqual(market["name"] as? String, CodexPluginProvenance.marketplaceName)
    }

    func testTheAppWiresTheRow() throws {
        let main = try source("Sources/Hats/main.swift")
        let menu = try source("Sources/Hats/AppDelegate+Menu.swift")
        let codex = try source("Sources/Hats/AppDelegate+Codex.swift")
        let panel = try source("Sources/Hats/GeneralPanel.swift")
        let flow = try source("Sources/Hats/CodexPluginFlow.swift")

        XCTAssertTrue(main.contains("lazy var codexPlugin = CodexPluginFlow.real(CodexPluginProvenance.bundledVersion)"))
        XCTAssertTrue(menu.contains("self.codexPlugin.refresh(then: nil)"), "opening Settings reads the state")
        XCTAssertTrue(codex.contains("        offerTheCodexPluginUpdateOnce()\n"), "told at launch")
        XCTAssertTrue(flow.contains("let work = SessionHandoffWork(world: .real)"),
                      "the work stops starting commands when Hats quits")
        let claudeRow = try XCTUnwrap(panel.range(of: "SessionHandoffRowView("))
        let codexRow = try XCTUnwrap(panel.range(of: "CodexPluginRowView("))
        XCTAssertLessThan(claudeRow.lowerBound, codexRow.lowerBound, "the Codex row is under the Claude one")
    }

    func testThePluginIsNotPutIntoTheApp() throws {
        let build = try source("Build/build-app.sh")

        XCTAssertFalse(build.contains("codex-plugin"))
    }
}
