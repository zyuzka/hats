import Foundation

enum GatewayStopDecision: Equatable {
    case proceed
    case ask(String)

    static func of(enabled: Bool,
                   ports: [Int],
                   sessions: @autoclosure () -> [Session]?) -> GatewayStopDecision {
        guard !enabled else { return .proceed }
        guard let cost = HatsCopy.gatewayStopCost(ports: ports, sessions: sessions()) else {
            return .proceed
        }
        return .ask(cost)
    }

    static func forARestart(ports: [Int],
                            sessions: @autoclosure () -> [Session]?) -> GatewayStopDecision {
        guard let cost = HatsCopy.gatewayRestartCost(ports: ports, sessions: sessions()) else {
            return .proceed
        }
        return .ask(cost)
    }
}
