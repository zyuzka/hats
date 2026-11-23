import XCTest
@testable import Hats

final class PopoverSettleTests: XCTestCase {
    func testWithThePopoverShownItClosesFirstAndAsksLater() {
        // Arrange
        var calls: [String] = []
        var deferred: (() -> Void)?

        // Act
        PopoverSettle.run(
            isShown: true,
            close: { calls.append("close") },
            later: { work in
                calls.append("later")
                deferred = work
            },
            work: { calls.append("ask") }
        )
        let beforeTheDelay = calls
        deferred?()

        // Assert
        XCTAssertEqual(beforeTheDelay, ["close", "later"], "the question waits until the popover has gone")
        XCTAssertEqual(calls, ["close", "later", "ask"])
    }

    func testWithoutThePopoverItAsksAtOnce() {
        // Arrange
        var calls: [String] = []

        // Act
        PopoverSettle.run(
            isShown: false,
            close: { calls.append("close") },
            later: { _ in calls.append("later") },
            work: { calls.append("ask") }
        )

        // Assert
        XCTAssertEqual(
            calls,
            ["ask"],
            "from the settings window the Codex question comes before the close question, so Discard cannot be followed by it"
        )
    }

    func testTheCodexGatewayQuestionWaitsOnlyForAShownPopover() throws {
        // Arrange
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("Sources/Hats/AppDelegate+CodexGatewayActions.swift")

        // Act
        let source = try String(contentsOf: path, encoding: .utf8)

        // Assert
        XCTAssertTrue(source.contains("PopoverSettle.run(\n            isShown: popover.isShown,"))
        XCTAssertFalse(source.contains("popover.close()\n        afterThePopoverSettles"))
    }
}
