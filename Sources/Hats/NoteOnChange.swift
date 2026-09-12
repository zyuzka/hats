import Foundation

struct NoteOnChange: Equatable {
    private var last: String?

    mutating func shouldWrite(_ observation: String) -> Bool {
        guard last != observation else { return false }
        last = observation

        return true
    }

    mutating func clear() { last = nil }
}
