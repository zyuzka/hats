import Foundation

enum ChromeChannel: String, Codable, Equatable, CaseIterable {
    case stable = "Chrome"
    case beta = "Chrome Beta"
    case dev = "Chrome Dev"
    case canary = "Chrome Canary"

    var application: String { "Google \(rawValue)" }

    var label: String { rawValue }

    var supportDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Google")
            .appendingPathComponent(rawValue)
    }

    var profiles: [String] { readableProfiles ?? [] }

    var readableProfiles: [String]? {
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: supportDirectory.path)
        } catch {
            guard FileManager.default.fileExists(atPath: supportDirectory.path) else { return [] }
            Journal.log("browser.profilesUnreadable", ["channel": rawValue, "error": error.localizedDescription])
            return nil
        }

        return entries
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted()
    }
}
