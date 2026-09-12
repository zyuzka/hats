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
