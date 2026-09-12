import Foundation

enum GatewayRefusedTarget {
    static func note(uri: String, path: String, session: String?, credential: String) -> [String: String] {
        [
            "uri": uri,
            "path": path,
            "session": session ?? "-",
            "credential": credential,
        ]
    }
}
