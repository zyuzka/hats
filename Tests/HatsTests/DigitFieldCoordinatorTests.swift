import AppKit
import XCTest
@testable import Hats

final class DigitFieldCoordinatorTests: XCTestCase {
    private final class Calls {
        var all: [String] = []
    }

    private func coordinator() -> (DigitFieldCoordinator, Calls) {
        let calls = Calls()
        let field = DigitField(
            text: "70",
            placeholder: "70",
            label: "Anchor at",
            change: { calls.all.append("change \($0)") },
            submit: { calls.all.append("submit") },
            cancel: { calls.all.append("cancel") }
        )

        return (DigitFieldCoordinator(field: field), calls)
    }

    private func type(_ text: String, into coordinator: DigitFieldCoordinator) {
        let view = NSTextField(string: text)
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: view))
    }

    private func endEditing(_ coordinator: DigitFieldCoordinator) {
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: nil))
    }

    private func press(_ selector: Selector, in coordinator: DigitFieldCoordinator) -> Bool {
        coordinator.control(NSTextField(), textView: NSTextView(), doCommandBy: selector)
    }

    func testTheFocusLeavingAfterAnEditSubmits() {
        // Arrange
        let (coordinator, calls) = coordinator()
        type("75", into: coordinator)

        // Act
        endEditing(coordinator)

        // Assert
        XCTAssertEqual(calls.all, [
            "change 75",
            "submit",
        ])
    }

    func testTheFocusLeavingWithoutAnEditSubmitsNothing() {
        // Arrange
        let (coordinator, calls) = coordinator()

        // Act
        endEditing(coordinator)

        // Assert
        XCTAssertEqual(calls.all, [])
    }

    func testTheFocusLeavingAfterEnterDoesNotSubmitTheSameTextAgain() {
        // Arrange
        let (coordinator, calls) = coordinator()
        type("9000", into: coordinator)
        _ = press(#selector(NSResponder.insertNewline(_:)), in: coordinator)

        // Act
        endEditing(coordinator)

        // Assert
        XCTAssertEqual(calls.all, [
            "change 9000",
            "submit",
        ], "a port the gateway refused is not sent again on every Tab")
    }

    func testEnterSubmitsEvenWithoutAnEdit() {
        // Arrange
        let (coordinator, calls) = coordinator()

        // Act
        let isHandled = press(#selector(NSResponder.insertNewline(_:)), in: coordinator)

        // Assert
        XCTAssertTrue(isHandled)
        XCTAssertEqual(calls.all, ["submit"], "Enter is an explicit retry")
    }

    func testEscCancelsAndTheFocusLeavingAfterItSubmitsNothing() {
        // Arrange
        let (coordinator, calls) = coordinator()
        type("65", into: coordinator)

        // Act
        let isHandled = press(#selector(NSResponder.cancelOperation(_:)), in: coordinator)
        endEditing(coordinator)

        // Assert
        XCTAssertTrue(isHandled)
        XCTAssertEqual(calls.all, [
            "change 65",
            "cancel",
        ])
    }

    func testEscThroughCompleteCancelsAndTheFocusLeavingAfterItSubmitsNothing() {
        // Arrange
        let (coordinator, calls) = coordinator()
        type("65", into: coordinator)

        // Act
        let isHandled = press(#selector(NSTextView.complete(_:)), in: coordinator)
        endEditing(coordinator)

        // Assert
        XCTAssertTrue(isHandled)
        XCTAssertFalse(coordinator.isEditedSinceSubmit)
        XCTAssertEqual(calls.all, [
            "change 65",
            "cancel",
        ])
    }

    func testOtherCommandsAreLeftToTheField() {
        // Arrange
        let (coordinator, calls) = coordinator()

        // Act
        let isHandled = press(#selector(NSResponder.insertTab(_:)), in: coordinator)

        // Assert
        XCTAssertFalse(isHandled)
        XCTAssertEqual(calls.all, [])
    }
}
