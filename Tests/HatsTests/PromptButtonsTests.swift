import XCTest
@testable import Hats

final class PromptButtonsTests: XCTestCase {
    func testTheFirstChoiceSitsOnTheRightAsItDoesEverywhereOnThisSystem() {
        let laidOut = PromptButtons.leftToRight(["Remove", "Cancel"])

        XCTAssertEqual(laidOut.map(\.title), ["Cancel", "Remove"])
        XCTAssertEqual(laidOut.map(\.index), [1, 0],
                       "callers read the answer as the index they passed in, so the layout may "
                           + "reorder the buttons but never renumber them")
    }

    func testThreeChoicesKeepTheirOrderToo() {
        let laidOut = PromptButtons.leftToRight(["Show it", "Cancel that sign-in", "Cancel"])

        XCTAssertEqual(laidOut.map(\.title), ["Cancel", "Cancel that sign-in", "Show it"])
    }

    func testReturnPicksTheFirstAndEscapePicksTheLast() {
        XCTAssertTrue(PromptButtons.isDefault(0, of: 3))
        XCTAssertFalse(PromptButtons.isDefault(1, of: 3))
        XCTAssertTrue(PromptButtons.isCancel(2, of: 3))
        XCTAssertFalse(PromptButtons.isCancel(1, of: 3))
    }

    func testASingleButtonIsBothTheDefaultAndTheWayOut() {
        XCTAssertTrue(PromptButtons.isDefault(0, of: 1))
        XCTAssertTrue(PromptButtons.isCancel(0, of: 1),
                      "an OK-only notice has to close on Escape as well, or it traps the keyboard")
    }

    func testTheAnswerWhenAWindowIsDismissedIsTheWayOut() {
        XCTAssertEqual(PromptButtons.dismissed(of: 3), 2)
        XCTAssertEqual(PromptButtons.dismissed(of: 1), 0,
                       "closing the window has to mean the same as pressing the last button, or a "
                           + "dismissed confirmation would read as consent")
    }
}
