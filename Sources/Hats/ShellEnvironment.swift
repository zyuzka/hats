import Foundation

enum ShellEnvironment {
    static let baseURLName = "ANTHROPIC_BASE_URL"

    static let openMarker = "# >>> hats gateway >>>"
    static let closeMarker = "# <<< hats gateway <<<"

    static let legacyOpenMarker = "# >>> acc-switch gateway >>>"
    static let legacyCloseMarker = "# <<< acc-switch gateway <<<"

    private static var markerPairs: [(open: String, close: String)] {
        [(openMarker, closeMarker), (legacyOpenMarker, legacyCloseMarker)]
    }

    private static func rangeOfManagedBlock(in profile: String) -> Range<String.Index>? {
        for pair in markerPairs {
            guard let start = profile.range(of: pair.open) else { continue }
            let rest = start.upperBound..<profile.endIndex
            guard let end = profile.range(of: pair.close, range: rest) else { continue }
            return start.lowerBound..<end.upperBound
        }
        return nil
    }

    enum Verdict: Equatable {
        case absent
        case ours
        case oursOutdated(current: String)
        case foreign(value: String)
        case foreignUnreadable
        case withdrawn
        case unreadable
    }

    private enum Found: Equatable {
        case absent
        case ours
        case oursOutdated(current: String)
        case foreign(value: String)
        case foreignUnreadable

        var verdict: Verdict {
            switch self {
            case .absent: return .absent
            case .ours: return .ours
            case .oursOutdated(let current): return .oursOutdated(current: current)
            case .foreign(let value): return .foreign(value: value)
            case .foreignUnreadable: return .foreignUnreadable
            }
        }
    }

    static func verdict(
        profile: String,
        baseURL: String,
        dialect: ShellDialect,
        serving: Bool
    ) -> Verdict {
        let found = found(in: profile, baseURL: baseURL, dialect: dialect)
        if serving { return found.verdict }
        if case .foreign = found { return found.verdict }
        if case .foreignUnreadable = found { return found.verdict }

        return .withdrawn
    }

    private static func found(in profile: String, baseURL: String, dialect: ShellDialect) -> Found {
        if let managed = managedBlock(in: profile) {
            if managed == block(baseURL: baseURL, dialect: dialect) { return .ours }
            return .oursOutdated(current: exportedBaseURL(in: managed, dialect: dialect) ?? "")
        }
        if let value = exportedBaseURL(in: profile, dialect: dialect) {
            return .foreign(value: value)
        }
        if containsAnAssignmentToBaseURL(in: profile, dialect: dialect) { return .foreignUnreadable }
        return .absent
    }

    static func applied(
        to profile: String,
        baseURL: String,
        dialect: ShellDialect,
        serving: Bool
    ) -> String? {
        guard serving else { return removed(from: profile) }

        switch found(in: profile, baseURL: baseURL, dialect: dialect) {
        case .ours, .foreign, .foreignUnreadable:
            return nil
        case .absent:
            let kept = isBlank(profile) ? "" : profile
            return kept + gap(after: kept)
                + block(baseURL: baseURL, dialect: dialect) + "\n"
        case .oursOutdated:
            guard let managed = managedBlock(in: profile) else { return nil }
            return profile.replacingOccurrences(
                of: managed,
                with: block(baseURL: baseURL, dialect: dialect)
            )
        }
    }

    static func removed(from profile: String) -> String? {
        guard let managed = rangeOfManagedBlock(in: profile) else { return nil }

        var head = String(profile[..<managed.lowerBound])
        var tail = String(profile[managed.upperBound...])
        while head.hasSuffix("\n") { head.removeLast() }
        while tail.hasPrefix("\n") { tail.removeFirst() }

        if isBlank(head) { return tail }
        if tail.isEmpty { return head + "\n" }
        return head + "\n\n" + tail
    }

    private static func isBlank(_ text: String) -> Bool {
        text.allSatisfy { $0.isWhitespace }
    }

    private static func gap(after profile: String) -> String {
        if profile.isEmpty || profile.hasSuffix("\n\n") { return "" }
        return profile.hasSuffix("\n") ? "\n" : "\n\n"
    }

    private static func managedBlock(in profile: String) -> String? {
        guard let managed = rangeOfManagedBlock(in: profile) else { return nil }
        return String(profile[managed])
    }

    private static func containsAnAssignmentToBaseURL(in text: String, dialect: ShellDialect) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).contains {
            dialect.containsAnAssignment(to: baseURLName, in: String($0))
        }
    }

    private static func exportedBaseURL(
        in text: String,
        dialect: ShellDialect
    ) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let value = dialect.value(in: String(line), name: baseURLName) {
                return value
            }
        }
        return nil
    }
}
