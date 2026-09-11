import Foundation

enum JournalDestination: Equatable {
    case theOperatorsLog
    case standardError

    static func of(bundleIdentifier: String?, ours: String) -> JournalDestination {
        bundleIdentifier == ours ? .theOperatorsLog : .standardError
    }
}
