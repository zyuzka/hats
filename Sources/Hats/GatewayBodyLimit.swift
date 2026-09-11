import Foundation
import NIOHTTP1

enum GatewayBodyLimit {
    static let maxBytes = 64 * 1024 * 1024

    static func allowsDeclaredLength(in headers: HTTPHeaders, limit: Int) -> Bool {
        guard let raw = headers.first(name: "content-length"),
              let declared = Int(raw.trimmingCharacters(in: .whitespaces))
        else { return true }
        return declared <= limit
    }

    static func allows(buffered: Int, incoming: Int, limit: Int) -> Bool {
        buffered + incoming <= limit
    }
}
