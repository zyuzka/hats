import Foundation

struct GatewayAddresses: Equatable {
    let current: String
    let retired: String?

    var all: [String] { [current] + (retired.map { [$0] } ?? []) }

    static func of(currentPort: Int, retiredPort: Int?) -> GatewayAddresses {
        GatewayAddresses(
            current: GatewayProcess.baseURL(port: currentPort),
            retired: retiredPort.map { GatewayProcess.baseURL(port: $0) }
        )
    }
}
