import Foundation

enum ChromeProfiles {
    static func key(_ channel: ChromeChannel, _ profile: String) -> String {
        "\(channel.rawValue)/\(profile)"
    }

    static func localStateURL(_ channel: ChromeChannel = .stable) -> URL {
        channel.supportDirectory.appendingPathComponent("Local State")
    }

    static func names() -> [String: String] {
        var named: [String: String] = [:]
        for channel in ChromeChannel.allCases {
            guard let data = try? Data(contentsOf: localStateURL(channel)) else { continue }
            for (profile, name) in names(localState: data) {
                named[key(channel, profile)] = name
            }
        }
        return named
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
