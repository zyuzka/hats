import AppKit

enum MarkState: Equatable {
    case idle
    case wearing(percent: Int?)
    case attention

    var hasMeter: Bool {
        guard case .wearing(let percent?) = self else { return false }
        return percent >= Mark.meterFrom
    }

    static func decide(
        anyHatBlocked: Bool,
        gatewayEnabled: Bool,
        gatewayServing: Bool,
        wearing: Bool,
        percent: Int?
    ) -> MarkState {
        if anyHatBlocked || (gatewayEnabled && !gatewayServing) { return .attention }
        guard wearing else { return .idle }
        return .wearing(percent: percent)
    }
}

enum Mark {
    static let letters = "hats"
    static let meterFrom = 70

    static func image(state: MarkState, cursorVisible: Bool = true, pointSize: CGFloat = 16) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: pointSize * 0.78, weight: .semibold)
        let text = NSAttributedString(string: letters, attributes: [
            .font: font, .foregroundColor: NSColor.black, .kern: -0.3,
        ])
        let textSize = text.size()
        let capHeight = font.capHeight
        let gap = pointSize * 0.14
        let cursorWidth = pointSize * 0.36
        let size = NSSize(width: ceil(textSize.width + gap + cursorWidth + 1), height: ceil(pointSize + 2))

        let image = NSImage(size: size, flipped: false) { _ in
            let baseline = (size.height - textSize.height) / 2
            text.draw(at: NSPoint(x: 0.5, y: baseline))
            let cursor = NSRect(
                x: 0.5 + textSize.width + gap,
                y: baseline + font.descender.magnitude,
                width: cursorWidth,
                height: capHeight
            )
            drawCursor(state, in: cursor, visible: cursorVisible)
            if state.hasMeter, case .wearing(let percent?) = state {
                drawMeter(percent: percent, under: NSRect(x: 0.5, y: baseline - 1, width: textSize.width, height: 0))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawCursor(_ state: MarkState, in rect: NSRect, visible: Bool) {
        guard visible else { return }
        NSColor.black.set()
        switch state {
        case .idle:
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        case .wearing:
            rect.fill()
        case .attention:
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
            let dot = rect.insetBy(dx: rect.width * 0.28, dy: rect.height * 0.36)
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    private static func drawMeter(percent: Int, under line: NSRect) {
        let full = NSRect(x: line.minX, y: line.minY - 1.5, width: line.width, height: 1.5)
        NSColor.black.withAlphaComponent(0.25).set()
        full.fill()
        NSColor.black.set()
        let share = CGFloat(min(percent, 100)) / 100
        NSRect(x: full.minX, y: full.minY, width: full.width * share, height: full.height).fill()
    }
}
