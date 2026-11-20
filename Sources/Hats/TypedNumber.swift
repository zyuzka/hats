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
    static func typed(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func getDigits(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { ("0"..."9").contains($0) }))
    }

    static func getDigitEdit(_ text: String, cursor: Int) -> (text: String, cursor: Int) {
        let before = (text as NSString).substring(to: min(max(0, cursor), (text as NSString).length))

        return (getDigits(text), getDigits(before).utf16.count)
    }

    static func getPercentDecision(_ text: String, current: Int, bounds: PercentBounds) -> PercentDecision {
        getRangeDecision(text, current: current, range: bounds.getStepRange())
    }

    static func getRangeDecision(_ text: String, current: Int, range: ClosedRange<Int>) -> PercentDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .silent }
        guard let value = typed(trimmed) else { return .refuse(getUnparsedRefusal(trimmed)) }
        if value < range.lowerBound { return .refuse(.belowLower) }
        if value > range.upperBound { return .refuse(.aboveUpper) }
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
