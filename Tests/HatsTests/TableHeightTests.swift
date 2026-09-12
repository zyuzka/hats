import XCTest
@testable import Hats

final class TableHeightTests: XCTestCase {
    func testOneRowGetsTheHeaderAndExactlyOneRow() {
        XCTAssertEqual(TableHeight.forRows(1, upTo: 12),
                       TableHeight.header + TableHeight.row,
                       "a single relay session used to sit in ninety fixed points, which showed "
                           + "half of it and two empty stripes underneath")
    }

    func testAnEmptyTableStillShowsItsHeaderAndOneRowOfRoom() {
        XCTAssertEqual(TableHeight.forRows(0, upTo: 12), TableHeight.forRows(1, upTo: 12))
    }

    func testALongTableStopsAtTheCeilingAndScrollsFromThere() {
        XCTAssertEqual(TableHeight.forRows(200, upTo: 12), TableHeight.forRows(12, upTo: 12),
                       "past the ceiling scrolling is the right answer; below it the scroll bar "
                           + "was noise")
    }

    func testEveryHeightIsAWholeNumberOfRowsSoNothingIsCutInHalf() {
        for count in 1...20 {
            let height = TableHeight.forRows(count, upTo: 12)
            let rows = (height - TableHeight.header) / TableHeight.row

            XCTAssertEqual(rows, rows.rounded(), "row \(count) landed on a fraction: \(height)")
        }
    }
}
