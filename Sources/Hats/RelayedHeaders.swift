import Foundation

extension UpstreamRelay {
    static let decodedByURLSession: Set<String> = ["content-encoding", "content-length"]

    static func relayedHeaders(from upstream: [AnyHashable: Any]) -> [(String, String)] {
        var out: [(String, String)] = []
        for (name, value) in upstream {
            guard let name = name as? String, let value = value as? String else { continue }
            let lowered = name.lowercased()
            guard !GatewayForward.hopByHop.contains(lowered) else { continue }
            guard !decodedByURLSession.contains(lowered) else { continue }
            out.append((name, value))
        }
        return out
    }
}
