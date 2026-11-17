import AppKit
import XCTest
@testable import Hats

final class HatMarkTests: XCTestCase {
    private let side = 320

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func coverage(_ draw: (NSRect) -> Void) throws -> [Bool] {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        var covered: [Bool] = []
        for y in 0..<side {
            for x in 0..<side {
                covered.append((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5)
            }
        }
        return covered
    }

    private func codeMark(in svgRect: CGRect) -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32), flipped: true) { _ in
            NSColor.black.setFill()
            let path = NSBezierPath(cgPath: HatMark.path(in: svgRect))
            path.fill()
            return true
        }
    }

    func testTheCodeDrawsTheSameShapeAsTheMarkFile() throws {
        let svg = try XCTUnwrap(NSImage(contentsOf: repositoryRoot().appendingPathComponent("docs/mark.svg")))
        let fromFile = try coverage { svg.draw(in: $0) }
        let fromCode = try coverage { codeMark(in: HatMark.drawing).draw(in: $0) }
        let both = zip(fromFile, fromCode).filter { $0 && $1 }.count
        let either = zip(fromFile, fromCode).filter { $0 || $1 }.count
        XCTAssertGreaterThan(both, 0)
        XCTAssertGreaterThan(Double(both) / Double(either), 0.97,
                             "the code path must cover the same pixels as docs/mark.svg: a shifted brim, "
                                 + "a flipped dome or a stretched shape all lower this overlap")
    }

    private func overlapWithTheFile(flipped: Bool = true, transform: AffineTransform = .identity) throws -> Double {
        let svg = try XCTUnwrap(NSImage(contentsOf: repositoryRoot().appendingPathComponent("docs/mark.svg")))
        let fromFile = try coverage { svg.draw(in: $0) }
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: flipped) { _ in
            NSColor.black.setFill()
            let path = NSBezierPath(cgPath: HatMark.path(in: HatMark.drawing))
            path.transform(using: transform)
            path.fill()
            return true
        }
        let fromCode = try coverage { image.draw(in: $0) }
        let both = zip(fromFile, fromCode).filter { $0 && $1 }.count
        let either = zip(fromFile, fromCode).filter { $0 || $1 }.count

        return Double(both) / Double(either)
    }

    func testAFlippedShiftedOrStretchedMarkFallsUnderTheThreshold() throws {
        XCTAssertGreaterThan(try overlapWithTheFile(), 0.97)
        XCTAssertLessThan(try overlapWithTheFile(flipped: false), 0.97, "upside down")
        XCTAssertLessThan(try overlapWithTheFile(transform: AffineTransform(translationByX: 0, byY: 1.2)), 0.97,
                          "shifted down by 1.2 of the 32 units")
        var stretch = AffineTransform(translationByX: 16, byY: 15.7)
        stretch.scale(x: 1, y: 1.2)
        stretch.translate(x: -16, y: -15.7)
        XCTAssertLessThan(try overlapWithTheFile(transform: stretch), 0.97, "stretched 1.2 times in height")
    }

    func testTheMarkKeepsItsProportionsInAnyFrame() {
        for frame in [CGRect(x: 0, y: 0, width: 14, height: 14), CGRect(x: 3, y: 5, width: 40, height: 7)] {
            let box = HatMark.path(in: frame).boundingBoxOfPath
            XCTAssertEqual(box.width / box.height, HatMark.drawing.width / HatMark.drawing.height, accuracy: 0.02)
            XCTAssertTrue(frame.insetBy(dx: -0.01, dy: -0.01).contains(box), "\(box) in \(frame)")
            XCTAssertEqual(box.midX, frame.midX, accuracy: 0.01)
            XCTAssertEqual(box.midY, frame.midY, accuracy: 0.01)
        }
        XCTAssertEqual(HatMark.rowWidth, 14)
    }

    private func hex(_ color: NSColor, in appearance: NSAppearance.Name) throws -> String {
        var resolved: NSColor?
        try XCTUnwrap(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        let srgb = try XCTUnwrap(resolved)
        let parts = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].map { Int(($0 * 255).rounded()) }
        return parts.map { String(format: "%02X", $0) }.joined()
    }

    func testClaudeIsTerracottaAndLighterInTheDark() throws {
        XCTAssertEqual(try hex(Tool.claudeCode.hatColor, in: .aqua), "D97757")
        XCTAssertEqual(try hex(Tool.claudeCode.hatColor, in: .darkAqua), "E8957A")
        XCTAssertEqual(try hex(ProviderColors.codex, in: .aqua), "5C6370")
        XCTAssertEqual(try hex(ProviderColors.codex, in: .darkAqua), "9AA1AD")
    }
}
