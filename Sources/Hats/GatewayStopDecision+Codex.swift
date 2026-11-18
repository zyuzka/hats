import Foundation

extension GatewayStopDecision {
    static func ofRemoving(_ hat: Account, codexHats: [Account], isServing: Bool, threads: Int) -> GatewayStopDecision {
        guard hat.wornTool == .codex, isServing, codexHats.allSatisfy({ $0.id == hat.id }) else { return .proceed }
        guard let cost = HatsCopy.codexGatewayStopCost(threads: threads) else { return .proceed }
        return .ask(cost)
    }
}
