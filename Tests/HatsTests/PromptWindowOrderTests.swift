import XCTest
@testable import Hats

final class PromptWindowOrderTests: XCTestCase {
    func testTheWindowIsShownBeforeTheModalLoopStarts() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/PromptWindow.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        let shown = try XCTUnwrap(text.range(of: "makeKeyAndOrderFront")?.lowerBound,
                                  "runModal alone left the window behind whatever was already open, "
                                      + "and a modal loop with an invisible window reads as the whole "
                                      + "app having frozen — measured on a live machine, the settings "
                                      + "window stopped responding after Check for Updates")
        let modal = try XCTUnwrap(text.range(of: "runModal")?.lowerBound)

        XCTAssertLessThan(shown, modal, "the window has to be on screen before the loop blocks input")
    }

    func testTheWindowIsOnScreenBeforeTheAppIsActivated() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/PromptWindow.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        let shown = try XCTUnwrap(text.range(of: "makeKeyAndOrderFront")?.lowerBound)
        let activated = try XCTUnwrap(text.range(of: "NSApp.activate")?.lowerBound)

        XCTAssertLessThan(shown, activated,
                          "activating first sends macOS to whichever window it thinks is the main "
                              + "one, and it took the person to another desktop while the window "
                              + "stayed put. Every other window in this app already shows itself "
                              + "first and activates after")
    }

    func testTheWindowSitsAboveTheOneThatAskedForIt() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/PromptWindow.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        XCTAssertTrue(text.contains("level = .modalPanel"),
                      "at the ordinary window level it can still end up behind the settings window "
                          + "that opened it")
    }
}
