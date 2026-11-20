import Foundation

struct CodexGatewayHats: Equatable {
    var all: [CodexTicket] = []
    var candidates: [CodexTicket] = []

    func next(after hatID: String, skipping tried: Set<String>) -> [CodexTicket] {
        let start = (candidates.firstIndex { $0.id == hatID }).map { $0 + 1 } ?? 0
        let ordered = Array(candidates[start...]) + Array(candidates[..<start])
        return ordered.filter { !tried.contains($0.id) && $0.id != hatID && !$0.needsSignIn }
    }

    func hasEveryoneRefused(_ tried: Set<String>) -> Bool {
        candidates.filter { !$0.needsSignIn }.allSatisfy { tried.contains($0.id) }
    }
}

enum CodexGatewayWanted {
    static func isWanted(hasCodexHats: Bool, enabled: Bool?) -> Bool {
        hasCodexHats && (enabled ?? true)
    }
}

struct CodexGatewayInputs: Equatable {
    let hats: CodexGatewayHats
    let wanted: Bool
    let port: Int
    let secret: String?
}
