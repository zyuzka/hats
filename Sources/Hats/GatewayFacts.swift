import Foundation

struct GatewayFacts: Equatable {
    let addresses: GatewayAddresses
    let isServing: Bool
    let settleSeconds: Int

    static func of(snapshot: HatsSnapshot) -> GatewayFacts {
        GatewayFacts(
            addresses: snapshot.gatewayAddresses,
            isServing: snapshot.gateway.isServing,
            settleSeconds: snapshot.settings.gatewaySettleSeconds
        )
    }
}
