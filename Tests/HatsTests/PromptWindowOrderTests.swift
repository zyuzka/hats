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
