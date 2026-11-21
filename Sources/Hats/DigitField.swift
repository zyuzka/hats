import AppKit
import SwiftUI

struct DigitField: NSViewRepresentable {
    let text: String
    let placeholder: String
    let label: String
    let change: (String) -> Void
    let submit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> DigitFieldCoordinator {
        DigitFieldCoordinator(field: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let view = NSTextField(string: text)
        view.placeholderString = placeholder
        view.bezelStyle = .roundedBezel
        view.controlSize = .small
        view.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        view.formatter = DigitFormatter()
        view.delegate = context.coordinator
        view.setAccessibilityLabel(label)

        return view
    }

    func updateNSView(_ view: NSTextField, context: Context) {
        context.coordinator.field = self
        view.placeholderString = placeholder
        if let editor = view.currentEditor() {
            if editor.string != text { editor.string = text }
            return
        }
        if view.stringValue != text { view.stringValue = text }
    }
}

final class DigitFieldCoordinator: NSObject, NSTextFieldDelegate {
    var field: DigitField
    private(set) var isEditedSinceSubmit = false

    init(field: DigitField) {
        self.field = field
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let view = notification.object as? NSTextField else { return }
        let editor = notification.userInfo?["NSFieldEditor"] as? NSText
        isEditedSinceSubmit = true
        field.change(TypedNumber.getDigits(editor?.string ?? view.stringValue))
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard isEditedSinceSubmit else { return }
        submit()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            control.window?.makeFirstResponder(nil)
            return true
        }
        guard selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSTextView.complete(_:))
        else { return false }
        isEditedSinceSubmit = false
        field.cancel()

        return true
    }

    private func submit() {
        isEditedSinceSubmit = false
        field.submit()
    }
}

final class DigitFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        obj as? String
    }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = TypedNumber.getDigits(string) as NSString
        return true
    }

    override func isPartialStringValid(
        _ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
        proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
        originalString origString: String,
        originalSelectedRange origSelRange: NSRange,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        let partial = partialStringPtr.pointee as String
        let cursor = proposedSelRangePtr?.pointee.location ?? (partial as NSString).length
        let edit = TypedNumber.getDigitEdit(partial, cursor: cursor)
        guard edit.text != partial else { return true }
        partialStringPtr.pointee = edit.text as NSString
        proposedSelRangePtr?.pointee = NSRange(location: edit.cursor, length: 0)

        return false
    }
}
