import Foundation

enum StateDirectory {
    static let directoryName = "Hats"
    static let overrideName = "HATS_STATE_HOME"

    static var url: URL {
        if let override = overrideURL { return override }
        _ = adoptionOfLegacyLocations

        return current
    }

    static var current: URL {
        if let override = overrideURL { return override }

        return defaultLocation
    }

    static var defaultLocation: URL {
        applicationSupport.appendingPathComponent(directoryName)
    }

    static var legacyLocations: [URL] {
        let claude = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/state")

        return [
            claude.appendingPathComponent("hats"),
            claude.appendingPathComponent("acc-switch"),
        ]
    }

    private static var overrideURL: URL? {
        let override = ProcessInfo.processInfo.environment[overrideName] ?? ""
        guard !override.isEmpty else { return nil }

        return URL(fileURLWithPath: override)
    }

    private static var applicationSupport: URL {
        let known = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        if let known { return known }

        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
    }

    private static let adoptionOfLegacyLocations: Void = {
        for legacy in legacyLocations {
            adopt(from: legacy, to: current, using: FileManager.default)
        }
    }()

    static func adopt(from legacy: URL, to current: URL, using files: FileManager) {
        guard files.fileExists(atPath: legacy.path) else { return }
        guard let entries = try? files.contentsOfDirectory(atPath: legacy.path) else { return }

        if !files.fileExists(atPath: current.path) {
            try? files.createDirectory(at: current, withIntermediateDirectories: true)
        }

        for entry in entries {
            let source = legacy.appendingPathComponent(entry)
            let target = current.appendingPathComponent(entry)
            guard !files.fileExists(atPath: target.path) else { continue }
            try? files.moveItem(at: source, to: target)
        }

        if let left = try? files.contentsOfDirectory(atPath: legacy.path), left.isEmpty {
            try? files.removeItem(at: legacy)
        }
    }
}
