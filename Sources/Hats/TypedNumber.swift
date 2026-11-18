import Foundation

enum PercentRefusal: Equatable {
    case notAWholeNumber
    case belowLower
    case aboveUpper
}

enum PercentDecision: Equatable {
    case silent
    case apply(Int)
    case refuse(PercentRefusal)
}

struct PercentFieldState: Equatable {
    let reason: String?
    let applicable: Int?
}

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

    static func getPercentDecision(_ text: String, current: Int, bounds: PercentBounds) -> PercentDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .silent }
        guard let value = typed(trimmed) else { return .refuse(getUnparsedRefusal(trimmed)) }
        if value < bounds.lower.percent { return .refuse(.belowLower) }
        if value > bounds.upper.percent { return .refuse(.aboveUpper) }
        guard value != current else { return .silent }

        return .apply(value)
    }

    static func getPercentFieldState(
        _ text: String,
        current: Int?,
        bounds: PercentBounds,
        note: String?
    ) -> PercentFieldState {
        guard let current else { return PercentFieldState(reason: note, applicable: nil) }
        switch getPercentDecision(text, current: current, bounds: bounds) {
        case .silent:
            return PercentFieldState(reason: note, applicable: nil)
        case .apply(let value):
            return PercentFieldState(reason: note, applicable: value)
        case .refuse(let refusal):
            return PercentFieldState(reason: HatsCopy.getPercentRefusal(refusal, bounds: bounds), applicable: nil)
        }
    }

    private static func getUnparsedRefusal(_ trimmed: String) -> PercentRefusal {
        let isSigned = trimmed.hasPrefix("-") || trimmed.hasPrefix("+")
        let digits = isSigned ? trimmed.dropFirst() : Substring(trimmed)
        guard !digits.isEmpty, digits.allSatisfy({ ("0"..."9").contains($0) }) else { return .notAWholeNumber }

        return trimmed.hasPrefix("-") ? .belowLower : .aboveUpper
    }
}
