import Foundation

enum HatJournalLine {
    static func vacation(hat id: String, on: Bool, since: Date?) -> [String: String] {
        [
            "hat": String(id.prefix(8)),
            "on": String(on),
            "since": since.map { ISO8601DateFormatter().string(from: $0) } ?? "-",
        ]
    }

    static func removal(hat id: String, payload: Data?, deletionError: Error?) -> [String: String] {
        [
            "id": String(id.prefix(8)),
            "payload": Journal.fingerprint(payload),
            "credentialDeleted": deletionError == nil ? "true" : "failed",
            "deletionFailure": deletionError?.localizedDescription ?? "none",
        ]
    }
}
