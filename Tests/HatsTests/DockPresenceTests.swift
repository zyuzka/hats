import XCTest
@testable import Hats

final class DockPresenceTests: XCTestCase {
    private let popover = WindowFace(isVisible: true, canBecomeMain: false)
    private let menuBarItem = WindowFace(isVisible: true, canBecomeMain: false)
    private let settings = WindowFace(isVisible: true, canBecomeMain: true)
    private let closedSettings = WindowFace(isVisible: false, canBecomeMain: true)

    func testAWindowAPersonCanLookAtPutsTheAppInTheDock() {
        XCTAssertTrue(DockPresence.isNeeded(for: [menuBarItem, settings]),
                      "without a dock icon there is no way to raise a window that slipped behind "
                          + "something else, and no Cmd-Tab entry either")
    }

    func testTheMenuBarAndThePopoverAloneDoNot() {
        XCTAssertFalse(DockPresence.isNeeded(for: [menuBarItem, popover]),
                       "a popover closes the moment you click away, so an icon for it would blink "
                           + "in and out of the dock")
        XCTAssertFalse(DockPresence.isNeeded(for: []))
    }

    func testAClosedWindowStopsCountingOnceItIsGone() {
        XCTAssertFalse(DockPresence.isNeeded(for: [menuBarItem, closedSettings]))
    }

    func testOneOpenWindowIsEnoughEvenAmongClosedOnes() {
        XCTAssertTrue(DockPresence.isNeeded(for: [closedSettings, settings, popover]))
    }
}

final class DockBeforeTheWindowTests: XCTestCase {
    func testEveryWindowAsksForTheDockBeforeItOpens() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        var missing: [String] = []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains("NSWindow(") else { continue }
            guard !text.contains("DockPresence.aWindowIsAboutToOpen()") else { continue }
            missing.append(file.lastPathComponent)
        }

        XCTAssertEqual(missing, [],
                       "changing the app from accessory to regular makes macOS show the app, and "
                           + "it travels to whichever desktop it thinks the app lives on, taking "
                           + "the person with it. Measured on a live machine: the settings window "
                           + "opened here and the person was thrown to another desktop. Doing it "
                           + "before any window exists leaves macOS nowhere to go: \(missing)")
    }
}
