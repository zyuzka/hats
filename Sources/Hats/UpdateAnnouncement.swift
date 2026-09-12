import Foundation

enum UpdateAnnouncement {
    static let interval: TimeInterval = 6 * 3600
    static let firstCheckAfter: TimeInterval = 60

    static func isWorthAnnouncing(_ version: String, announced: String?) -> Bool {
        version != announced
    }
}
