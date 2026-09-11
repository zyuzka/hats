import Foundation

enum GatewayPortChange: Equatable {
    case unchanged
    case promoteRetired
    case bind

    static func plan(servingPort: Int?, retiredPort: Int?, requested: Int) -> GatewayPortChange {
        if servingPort == requested { return .unchanged }
        if retiredPort == requested { return .promoteRetired }
        return .bind
    }
}
