import Foundation

enum SessionsAtRisk {
    static let contentType = "text/plain; charset=utf-8"
    static let readable = "readable"
    static let pid = "pid"

    static func text(ports: [Int], sessions: [Session]?) -> String {
        guard let sessions else { return "\(readable) 0\n" }
        let pids = GatewayRetirement.dependants(onAnyOf: ports, among: sessions)
            .map(\.pid)
            .sorted()
        return (["\(readable) 1"] + pids.map { "\(pid) \($0)" }).joined(separator: "\n") + "\n"
    }

    static func body(ports: [Int], sessions: [Session]?) -> Data {
        Data(text(ports: ports, sessions: sessions).utf8)
    }
}
