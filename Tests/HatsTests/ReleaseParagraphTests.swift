import XCTest
@testable import Hats

final class ReleaseParagraphTests: XCTestCase {
    func testAWrappedBulletComesBackAsOneParagraph() {
        let lines = [
            "- **A parked hat keeps its own login alive.** An account you are not wearing sits in a slot",
            "  no Claude Code ever reads, so the renewal could never arrive there.",
        ]

        XCTAssertEqual(ReleaseNotes.paragraphs(lines), [
            "- **A parked hat keeps its own login alive.** An account you are not wearing sits in a "
                + "slot no Claude Code ever reads, so the renewal could never arrive there.",
        ], "the file wraps its own lines at about a hundred characters, and drawing each one as its "
            + "own line ignores how wide the window actually is")
    }

    func testTheNextBulletStartsItsOwnParagraph() {
        let lines = [
            "- first thing, which runs on",
            "  to a second line",
            "- second thing",
        ]

        XCTAssertEqual(ReleaseNotes.paragraphs(lines),
                       ["- first thing, which runs on to a second line", "- second thing"])
    }

    func testABlankLineSeparatesParagraphs() {
        let lines = ["one line", "still the same", "", "a new one"]

        XCTAssertEqual(ReleaseNotes.paragraphs(lines), ["one line still the same", "a new one"])
    }

    func testNothingInMeansNothingOut() {
        XCTAssertEqual(ReleaseNotes.paragraphs([]), [])
        XCTAssertEqual(ReleaseNotes.paragraphs(["", "  ", ""]), [])
    }
}
