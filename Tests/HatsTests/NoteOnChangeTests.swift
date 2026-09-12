import XCTest
@testable import Hats

final class NoteOnChangeTests: XCTestCase {
    func testTheSameObservationIsWrittenOnce() {
        var note = NoteOnChange()

        XCTAssertTrue(note.shouldWrite("live=a stored=b"))
        XCTAssertFalse(note.shouldWrite("live=a stored=b"),
                       "the live credential and the stored one differ for as long as the CLI has "
                           + "rotated its token, which is hours; writing that every poll put 72 "
                           + "identical lines into one day's journal — the file people are asked "
                           + "to send when something needs explaining")
    }

    func testAnObservationThatChangedIsWrittenAgain() {
        var note = NoteOnChange()
        _ = note.shouldWrite("live=a stored=b")

        XCTAssertTrue(note.shouldWrite("live=c stored=b"))
    }

    func testClearingMakesTheNextOneWorthWritingAgain() {
        var note = NoteOnChange()
        _ = note.shouldWrite("live=a stored=b")

        note.clear()

        XCTAssertTrue(note.shouldWrite("live=a stored=b"),
                      "once the two agree again, the next time they part is news")
    }
}
