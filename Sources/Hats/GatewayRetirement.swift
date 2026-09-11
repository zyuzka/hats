import Foundation

enum GatewayRetirement {
    static func dependants(on port: Int, among sessions: [Session]) -> [Session] {
        dependants(onAnyOf: [port], among: sessions)
    }

    static func dependants(onAnyOf ports: [Int], among sessions: [Session]) -> [Session] {
        let held = Set(ports)
        return sessions.filter { session in held.contains { session.route.isOnLoopback(port: $0) } }
    }

    static func isStillDependedOn(port: Int, by sessions: [Session]?) -> Bool {
        guard let sessions else { return true }
        return !dependants(on: port, among: sessions).isEmpty
    }

    enum Verdict: Equatable {
        case nothingRetired
        case releaseIt
        case keepIt
    }

    static func verdict(hasRetired: Bool, retiredPort: Int?, sessions: @autoclosure () -> [Session]?) -> Verdict {
        guard hasRetired else { return .nothingRetired }
        guard let retiredPort else { return .releaseIt }
        return isStillDependedOn(port: retiredPort, by: sessions()) ? .keepIt : .releaseIt
    }
}
