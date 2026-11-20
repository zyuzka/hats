import AppKit
import SwiftUI
import XCTest
@testable import Hats

final class UsageBarWidthTests: XCTestCase {
    private func redPixelsPerHalf(_ bars: [UsageBar], width: CGFloat) throws -> (Int, Int) {
        let view = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                UsageBarView(bar: bar, secondary: .gray, lit: false)
            }
        }
        .frame(width: width, alignment: .leading)
        .background(Color.white)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        var top = 0, bottom = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      c.redComponent > 0.8, c.greenComponent < 0.4, c.blueComponent < 0.4 else { continue }
                if y < rep.pixelsHigh / 2 { top += 1 } else { bottom += 1 }
            }
        }
        return (top, bottom)
    }

    func testBothBarsOfARowHaveTheSameLengthWhateverTheirResetText() throws {
        let short = UsageBar(label: "5h", percent: 100, tone: .critical, fill: .solid, resets: "01:42")
        let long = UsageBar(label: "week", percent: 100, tone: .critical, fill: .solid, resets: "Wed 28 Sep 22:42")
        let none = UsageBar(label: "week", percent: 100, tone: .critical, fill: .solid, resets: nil)
        for other in [long, none] {
            let (top, bottom) = try redPixelsPerHalf([short, other], width: 230)
            XCTAssertGreaterThan(top, 0)
            XCTAssertEqual(top, bottom, "the bar length must not depend on the reset text beside it")
        }
    }

    func testTheResetColumnFitsTheLongestDate() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        for text in ["Wed 28 Sep 22:42", "Mon 23 Nov 10:00", "Thu 30 May 00:00"] {
            let width = NSAttributedString(string: text, attributes: [.font: font]).size().width
            XCTAssertLessThanOrEqual(width, UsageBarView.resetsColumnWidth, text)
        }
    }

    func testEveryRowOfTheListHasTheSameBarLength() throws {
        let full = UsageWindow(used: 100, limit: 100, resetsAt: Date().addingTimeInterval(3 * 3600))
        let week = WeekSighting(
            window: UsageWindow(used: 100, limit: 100, resetsAt: Date().addingTimeInterval(6 * 86400)),
            isConfirmed: true
        )
        var worn = Account(id: "w", email: "another.long.address@company-name.example.com", browser: nil)
        worn.name = "Work account long title"
        var parked = Account(id: "p", email: "a.very.long.address.for.testing@some-company-name.example.com", browser: nil)
        parked.name = "Personal account with a long name"
        let reading = UsageReading(session: full, weekly: nil)
        let rows = [
            HatRowState(hat: worn, isWearing: true, usage: reading, usageTrouble: nil, week: week),
            HatRowState(hat: parked, isWearing: false, usage: reading, usageTrouble: nil, week: week),
        ]
        XCTAssertNotNil(rows[1].blocker, "the second row has «needs login» on the right")
        let view = VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                HatRowView(row: row, isChanging: false, handover: nil, display: .bars, tool: .claudeCode,
                           onWear: {}, onRelogin: {})
            }
        }
        .frame(width: 340)
        .background(Color.white)
        let lengths = try redRunLengths(of: view)
        XCTAssertEqual(lengths.count, 4, "two bars in each of the two rows: \(lengths)")
        XCTAssertEqual(Set(lengths).count, 1, "every bar of the list has one length: \(lengths)")
    }

    private func redRunLengths<V: View>(of view: V) throws -> [Int] {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        var bands: [Int] = []
        var inBand = false
        for y in 0..<rep.pixelsHigh {
            let count = (0..<rep.pixelsWide).filter { x in
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return c.redComponent > 0.8 && c.greenComponent < 0.4 && c.blueComponent < 0.4
            }.count
            if count > 0 {
                if inBand { bands[bands.count - 1] = max(bands[bands.count - 1], count) } else { bands.append(count) }
            }
            inBand = count > 0
        }
        return bands
    }
}
