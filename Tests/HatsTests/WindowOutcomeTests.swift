import XCTest
@testable import Hats

final class WindowOutcomeTests: XCTestCase {
    func testACountIsTakenFromTheScriptOutput() {
        XCTAssertEqual(WindowOutcome.parsed(status: 0, output: "2\n"), .counted(2))
        XCTAssertEqual(WindowOutcome.parsed(status: 0, output: "0"), .counted(0))
    }

    func testAFailedScriptIsNotACountOfZero() {
        XCTAssertEqual(WindowOutcome.parsed(status: 1, output: ""), .couldNotAsk)
        XCTAssertEqual(WindowOutcome.parsed(status: 1, output: "0"), .couldNotAsk)
    }

    func testOutputThatIsNotANumberIsNotACount() {
        XCTAssertEqual(WindowOutcome.parsed(status: 0, output: ""), .couldNotAsk)
        XCTAssertEqual(WindowOutcome.parsed(status: 0, output: "not allowed"), .couldNotAsk)
    }
}
