import Foundation

struct CodexGatewayFace: Equatable {
    var status = GatewayProcess.Status.notRunning
    var hasCodexHats = false
    var configNote: String?
    var threads = 0
}
