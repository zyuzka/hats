import AppKit
import XCTest
@testable import Hats

final class SessionHandoffWorkTests: XCTestCase {
    private func source(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/\(name)")

        return try String(contentsOf: url, encoding: .utf8)
    }

    func testAfterQuitNoCommandStarts() {
        let fake = FakePluginWorld()
        let center = NotificationCenter()
        let work = SessionHandoffWork(world: fake.world(), center: center)

        center.post(name: NSApplication.willTerminateNotification, object: nil)
        let outcome = work.world.run(PluginCommandLine(
            executable: FakePluginWorld.cli,
            arguments: SessionHandoffSteps.listArguments,
            environment: [:],
            seconds: 30
        ))

        XCTAssertTrue(work.isStopped)
        XCTAssertEqual(outcome.end, .notStarted("Hats is quitting"))
        XCTAssertEqual(fake.runs, [], "after Quit not one claude plugin command reaches the system")
    }

    func testBeforeQuitCommandsPassThrough() {
        let fake = FakePluginWorld()
        let work = SessionHandoffWork(world: fake.world(), center: NotificationCenter())

        _ = SessionHandoffSteps.findFace(in: work.world)

        XCTAssertFalse(fake.runs.isEmpty)
    }

    func testQuittingHatsNeitherRemovesThePluginNorCallsClaude() throws {
        let main = try source("main.swift")
        let start = try XCTUnwrap(main.range(of: "func applicationWillTerminate"))
        let end = try XCTUnwrap(main.range(of: "@objc private func markClicked", range: start.upperBound..<main.endIndex))
        let body = String(main[start.lowerBound..<end.lowerBound])

        for word in ["handoff", "Handoff", "plugin", "Plugin", "uninstall"] {
            XCTAssertFalse(body.contains(word), "applicationWillTerminate mentions \(word)")
        }
    }

    func testTheRealWorldRunsCommandsThroughTheGroupRunner() throws {
        let text = try source("PluginWorld.swift")

        XCTAssertTrue(text.contains("run: { GroupRun.getOutcome(of: $0) }"),
                      "asserted on the text: calling it for real would start claude on this machine")
        XCTAssertTrue(text.contains("liveSessions: { LiveCLISessions.find() }"))
    }

    func testTheAppHandsTheRealWorldToItsWork() throws {
        let main = try source("main.swift")

        XCTAssertTrue(main.contains("let handoffWork = SessionHandoffWork(world: .real)"))
        XCTAssertTrue(main.contains("perform: { [handoffWork] work in handoffWork.perform(work) }"))
        XCTAssertTrue(main.contains("ask: { PromptWindow.ask($0) == 0 }"),
                      "Install and Remove are the first buttons, index 0, of their windows")
    }

    func testOpeningTheSettingsReadsTheHandoffState() throws {
        let menu = try source("AppDelegate+Menu.swift")
        let start = try XCTUnwrap(menu.range(of: "func showSettings()"))
        let end = try XCTUnwrap(menu.range(of: "func toggleStartAtLogin()", range: start.upperBound..<menu.endIndex))

        XCTAssertTrue(menu[start.lowerBound..<end.lowerBound].contains("self.handoff.refresh()"))
    }
}
