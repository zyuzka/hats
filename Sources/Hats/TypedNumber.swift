import Foundation

enum TypedNumber {
    typealias Usable = (Int) -> Bool

    static func typed(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func applicable(_ text: String, current: Int, isUsable: Usable) -> Int? {
        guard let value = typed(text),
              isUsable(value),
              value != current
        else { return nil }
        return value
    }
}
