import Foundation

enum LiveSlotNow: Equatable {
    case holding(Data)
    case empty
    case unreadable

    static func hasChanged(from before: LiveSlotNow, to now: LiveSlotNow) -> Bool {
        switch (before, now) {
        case (.unreadable, _), (_, .unreadable):
            return false
        case (.holding(let before), .holding(let now)):
            return before != now
        case (.empty, .empty):
            return false
        case (.empty, .holding), (.holding, .empty):
            return true
        }
    }
}

enum RollbackDecision: Equatable {
    case restore
    case leaveForeignCredentialAlone
    case leaveUnreadableSlotAlone

    static func decide(now: LiveSlotNow, attempted: Data, liveBefore: Data?) -> RollbackDecision {
        switch now {
        case .unreadable:
            return .leaveUnreadableSlotAlone
        case .empty:
            return .restore
        case .holding(let current):
            if current == attempted { return .restore }
            if let liveBefore, current == liveBefore { return .restore }
            return .leaveForeignCredentialAlone
        }
    }
}
