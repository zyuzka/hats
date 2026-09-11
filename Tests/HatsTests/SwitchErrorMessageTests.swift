import XCTest
@testable import Hats

final class SwitchErrorMessageTests: XCTestCase {
    func testAFailedDeletionSaysTheItemIsStillThereRatherThanThatSomethingWasWritten() {
        let text = SwitchError.deletionDidNotTake("the credential this switch wrote")
            .errorDescription ?? ""
        XCTAssertTrue(text.contains("still holds the credential this switch wrote"))
        XCTAssertFalse(text.contains("after writing them"))
    }

    func testAFailedWriteAndAFailedDeletionDoNotShareOneMessage() {
        XCTAssertNotEqual(SwitchError.writeDidNotTake("x").errorDescription,
                          SwitchError.deletionDidNotTake("x").errorDescription)
    }
}
