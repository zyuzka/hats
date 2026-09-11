import AppKit

enum MarkClick: Equatable {
    case popover
    case menu

    static func of(_ event: NSEvent?) -> MarkClick {
        guard let event else { return .popover }
        return of(
            isSecondaryButton: event.type == .rightMouseUp || event.type == .rightMouseDown,
            holdsControl: event.modifierFlags.contains(.control)
        )
    }

    static func of(isSecondaryButton: Bool, holdsControl: Bool) -> MarkClick {
        isSecondaryButton || holdsControl ? .menu : .popover
    }
}
