import SwiftUI

enum HatMark {
    static let drawing = CGRect(x: 2.8, y: 8.6, width: 26.4, height: 14.2)
    static let rowWidth: CGFloat = 14

    static var rowHeight: CGFloat { rowWidth * drawing.height / drawing.width }

    static func path(in rect: CGRect) -> CGPath {
        let scale = min(rect.width / drawing.width, rect.height / drawing.height)
        let offsetX = rect.minX + (rect.width - drawing.width * scale) / 2 - drawing.minX * scale
        let offsetY = rect.minY + (rect.height - drawing.height * scale) / 2 - drawing.minY * scale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: offsetX + x * scale, y: offsetY + y * scale)
        }
        let path = CGMutablePath()
        path.move(to: point(9.2, 18.6))
        path.addCurve(to: point(16, 8.6), control1: point(8.6, 12.4), control2: point(11, 8.6))
        path.addCurve(to: point(22.8, 18.6), control1: point(21, 8.6), control2: point(23.4, 12.4))
        path.closeSubpath()
        addBrim(to: path, point: point)

        return path
    }

    private static func addBrim(to path: CGMutablePath, point p: (CGFloat, CGFloat) -> CGPoint) {
        let cx: CGFloat = 16, cy: CGFloat = 19.4, rx: CGFloat = 13.2, ry: CGFloat = 3.4
        let k: CGFloat = 0.552_284_75
        path.move(to: p(cx + rx, cy))
        path.addCurve(to: p(cx, cy + ry), control1: p(cx + rx, cy + ry * k), control2: p(cx + rx * k, cy + ry))
        path.addCurve(to: p(cx - rx, cy), control1: p(cx - rx * k, cy + ry), control2: p(cx - rx, cy + ry * k))
        path.addCurve(to: p(cx, cy - ry), control1: p(cx - rx, cy - ry * k), control2: p(cx - rx * k, cy - ry))
        path.addCurve(to: p(cx + rx, cy), control1: p(cx + rx * k, cy - ry), control2: p(cx + rx, cy - ry * k))
        path.closeSubpath()
    }
}

enum RowMark: Equatable {
    case hat(Tool)
    case blank

    static func of(_ row: HatRowState, tool: Tool) -> RowMark { row.isWearing ? .hat(tool) : .blank }
}

struct HatMarkShape: Shape {
    func path(in rect: CGRect) -> Path { Path(HatMark.path(in: rect)) }
}

struct HatMarkView: View {
    let tool: Tool

    var body: some View {
        HatMarkShape()
            .fill(Color(nsColor: tool.hatColor))
            .frame(width: HatMark.rowWidth, height: HatMark.rowHeight)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
    }
}
