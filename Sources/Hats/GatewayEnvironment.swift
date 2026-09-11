import Foundation

enum GatewayEnvironment {
    @discardableResult
    static func ensure(
        baseURL: String = GatewayProcess.baseURL,
        serving: Bool
    ) -> GatewayEnvironmentReport {
        switch resolveProfile() {
        case .refused(let report):
            return report
        case .profile(let profile):
            return apply(
                baseURL: baseURL,
                to: profile.existing,
                target: profile.target,
                serving: serving,
                existed: profile.existed
            )
        }
    }

    @discardableResult
    static func takeOver(baseURL: String = GatewayProcess.baseURL, serving: Bool) -> GatewayEnvironmentReport {
        guard serving else {
            Journal.log("gateway.takeoverRefused", ["reason": "notServing"])
            return ensure(baseURL: baseURL, serving: false)
        }
        let profile: ResolvedProfile
        switch resolveProfile() {
        case .refused(let report): return report
        case .profile(let resolved): profile = resolved
        }
        guard let updated = ShellEnvironment.takenOver(
            profile: profile.existing, baseURL: baseURL, dialect: profile.target.dialect
        ) else {
            Journal.log("gateway.takeoverRefused", ["profile": profile.target.path])
            return ensure(baseURL: baseURL, serving: true)
        }
        let wrote = hasWritten(updated, to: profile.url, previous: profile.existing, existed: profile.existed)
        Journal.log("gateway.takeover", ["profile": profile.target.path, "wrote": String(wrote)])
        let verdict: ShellEnvironment.Verdict = wrote
            ? .ours
            : ShellEnvironment.verdict(
                profile: profile.existing, baseURL: baseURL, dialect: profile.target.dialect, serving: true
            )
        return GatewayEnvironmentReport(verdict: verdict, profilePath: profile.target.path, wrote: wrote)
    }

    private static func apply(
        baseURL: String,
        to existing: String,
        target: ShellTarget,
        serving: Bool,
        existed: Bool
    ) -> GatewayEnvironmentReport {
        let verdict = ShellEnvironment.verdict(
            profile: existing,
            baseURL: baseURL,
            dialect: target.dialect,
            serving: serving
        )
        let updated = ShellEnvironment.applied(
            to: existing,
            baseURL: baseURL,
            dialect: target.dialect,
            serving: serving
        )
        let wrote = updated.map {
            hasWritten($0, to: URL(fileURLWithPath: target.path), previous: existing, existed: existed)
        } ?? false

        Journal.log("gateway.environment", [
            "verdict": name(of: verdict),
            "profile": target.path,
            "wrote": String(wrote),
        ])
        return GatewayEnvironmentReport(
            verdict: verdict,
            profilePath: target.path,
            wrote: wrote
        )
    }

    static func refused(
        _ verdict: ShellEnvironment.Verdict?,
        reason: String,
        profile: String?
    ) -> GatewayEnvironmentReport {
        Journal.log("gateway.environment", [
            "verdict": reason,
            "shell": ShellProfile.loginShell() ?? "-",
            "profile": profile ?? "-",
            "wrote": "false",
        ])
        return GatewayEnvironmentReport(verdict: verdict, profilePath: profile, wrote: false)
    }

    static func readable(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func hasWritten(
        _ updated: String,
        to url: URL,
        previous: String,
        existed: Bool
    ) -> Bool {
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            if existed { try keepFirstBackup(of: previous, beside: url) }
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            Journal.log("gateway.environmentFailed", ["reason": error.localizedDescription])
            return false
        }
    }

    private static func keepFirstBackup(of previous: String, beside url: URL) throws {
        let backup = url.appendingPathExtension("bak-hats")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }

        try previous.write(to: backup, atomically: true, encoding: .utf8)
    }

    private static func name(of verdict: ShellEnvironment.Verdict) -> String {
        switch verdict {
        case .absent: return "absent"
        case .ours: return "ours"
        case .oursOutdated: return "outdated"
        case .foreign: return "foreign"
        case .foreignUnreadable: return "foreign-unreadable"
        case .withdrawn: return "withdrawn"
        case .unreadable: return "unreadableProfile"
        }
    }
}
