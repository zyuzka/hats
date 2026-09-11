import Foundation

enum Tool: String, Codable, Equatable, CaseIterable {
    case claudeCode

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        }
    }
}
