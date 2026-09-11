import Foundation

enum ChromeProfiles {
    static var localStateURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
    }

    static func names() -> [String: String] {
        guard let data = try? Data(contentsOf: localStateURL) else { return [:] }
        return names(localState: data)
    }

    static func names(localState data: Data) -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [:] }

        var names: [String: String] = [:]
        for (directory, entry) in cache {
            guard let info = entry as? [String: Any], let name = displayName(info) else { continue }
            names[directory] = name
        }
        return names
    }

    private static func displayName(_ info: [String: Any]) -> String? {
        let name = text(info["name"]) ?? text(info["gaia_name"])
        let address = text(info["user_name"])
        switch (name, address) {
        case (nil, nil):
            return nil
        case (let name?, nil):
            return name
        case (nil, let address?):
            return address
        case (let name?, let address?):
            return name.localizedCaseInsensitiveContains(address) ? name : "\(name) (\(address))"
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
