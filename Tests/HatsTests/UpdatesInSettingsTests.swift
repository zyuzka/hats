import XCTest
@testable import Hats

private final class FakeUpdater: AppUpdater {
    var canCheckNow = true
    var checksAutomatically = true
    var hasAnUpdateWaiting = false
    var whenCanCheckNowChanges: (() -> Void)?

    func start() {}

    func checkNow() {}
}

final class UpdatesInSettingsTests: XCTestCase {
    func testWithoutAnUpdaterThereIsNoUpdateRow() {
        var snapshot = HatsSnapshot()
        snapshot.checksForUpdatesAutomatically = true
        snapshot.canCheckForUpdates = true

        snapshot.setUpdates(from: nil)

        XCTAssertNil(snapshot.checksForUpdatesAutomatically,
                     "a build without a feed has no updater, and a switch for it would do nothing")
        XCTAssertNil(snapshot.canCheckForUpdates)
        XCTAssertFalse(snapshot.hasAnUpdateWaiting)
    }

    func testTheUpdaterIsShownAsItIs() {
        let updater = FakeUpdater()
        updater.checksAutomatically = false
        updater.canCheckNow = false
        updater.hasAnUpdateWaiting = true
        var snapshot = HatsSnapshot()

        snapshot.setUpdates(from: updater)

        XCTAssertEqual(snapshot.checksForUpdatesAutomatically, false)
        XCTAssertEqual(snapshot.canCheckForUpdates, false)
        XCTAssertTrue(snapshot.hasAnUpdateWaiting)
    }

    func testTheButtonSaysAnUpdateIsWaitingAfterLater() throws {
        var snapshot = HatsSnapshot()
        XCTAssertEqual(snapshot.checkForUpdatesTitle, "Check for Updates\u{2026}")

        snapshot.hasAnUpdateWaiting = true

        XCTAssertEqual(snapshot.checkForUpdatesTitle, "Install the waiting update\u{2026}",
                       "after Later the button asks about the install at once, so its title says so")
        let panel = try sourceOf("GeneralPanel.swift")
        XCTAssertTrue(panel.contains("Button(snapshot.checkForUpdatesTitle)"))
        XCTAssertTrue(panel.contains("if let checks = snapshot.checksForUpdatesAutomatically {\n"
                                         + "                automaticUpdateChecksRow(checks)"),
                      "the switch row is drawn only when there is an updater")
        XCTAssertTrue(try sourceOf("AppDelegate+Redraw.swift").contains("snapshot.setUpdates(from: updater)"))
    }

    func testTogglingTheAutomaticCheckWritesTheNewStateToTheJournal() {
        let updater = FakeUpdater()
        var lines: [(String, [String: String])] = []

        AppUpdates.toggleAutomaticChecks(of: updater) { lines.append(($0, $1)) }

        XCTAssertFalse(updater.checksAutomatically)
        XCTAssertEqual(lines.map(\.0), ["update.automaticChecks"])
        XCTAssertEqual(lines.first?.1, ["enabled": "false"], "the journal names the state after the toggle")
    }

    func testTheMenuActionGoesThroughTheToggle() throws {
        let menu = try sourceOf("AppDelegate+Menu.swift")

        XCTAssertTrue(menu.contains("AppUpdates.toggleAutomaticChecks(of: updater) { Journal.log($0, $1) }"))
    }

    private func sourceOf(_ name: String) throws -> String {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/\(name)")

        return try String(contentsOf: source, encoding: .utf8)
    }
}
