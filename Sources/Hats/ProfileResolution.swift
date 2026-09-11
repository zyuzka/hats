import Foundation

struct ResolvedProfile {
    let target: ShellTarget
    let url: URL
    let existing: String
    let existed: Bool
}

extension GatewayEnvironment {
    enum Resolution {
        case profile(ResolvedProfile)
        case refused(GatewayEnvironmentReport)
    }

    static func resolveProfile() -> Resolution {
        guard let target = ShellProfile.currentTarget() else {
            return .refused(refused(nil, reason: "unknownShell", profile: nil))
        }
        let url = URL(fileURLWithPath: target.path)
        guard let existing = readable(url) else {
            return .refused(refused(.unreadable, reason: "unreadableProfile", profile: target.path))
        }
        let existed = FileManager.default.fileExists(atPath: url.path)
        return .profile(ResolvedProfile(target: target, url: url, existing: existing, existed: existed))
    }
}
