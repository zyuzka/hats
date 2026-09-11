import Foundation

extension GatewayProcess {
    static func outcome(started: Bool, serving: Bool) -> Status {
        guard started else { return .failed("the port could not be bound") }
        guard serving else { return .failed("bound but not serving") }
        return .running
    }
    static func refusalReason(of status: Status) -> String? {
        guard case .failed(let reason) = status else { return nil }
        return reason
    }
    static func reported(serving: Bool, last: Status?) -> Status {
        if serving { return .running }
        guard let last, case .failed = last else { return .notRunning }
        return last
    }

    enum Status: Equatable {
        case running
        case notRunning
        case failed(String)

        var isServing: Bool {
            switch self {
            case .running: return true
            case .notRunning, .failed: return false
            }
        }
    }
}
