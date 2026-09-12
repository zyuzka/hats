import CoreGraphics

enum TableHeight {
    static let row: CGFloat = 24
    static let header: CGFloat = 28

    static func forRows(_ count: Int, upTo ceiling: Int) -> CGFloat {
        header + row * CGFloat(min(max(count, 1), ceiling))
    }
}
