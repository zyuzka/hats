import Foundation

struct GatewayEnvironmentReport: Equatable {
    let verdict: ShellEnvironment.Verdict?
    let profilePath: String?
    let wrote: Bool

    var menuLine: String? {
        guard let verdict else {
            return "unknown login shell — set the three gateway variables yourself"
        }
        switch verdict {
        case .unreadable:
            return "the shell profile could not be read, so it was left alone — "
                + "new sessions bypass the gateway"
        case .withdrawn:
            return "the gateway is not serving, so its variables stay out of the profile — "
                + "new sessions bypass it"
        case .oursOutdated where wrote:
            return "the gateway block in the shell profile was updated — terminals already "
                + "open keep the old variables until they are reopened"
        case _ where wrote:
            return "shells opened from now on send their sessions through the gateway"
        case .ours:
            return nil
        case .absent, .oursOutdated:
            return "the shell profile could not be updated — new sessions bypass the gateway"
        case .foreign(let value):
            return "\(ShellEnvironment.baseURLName) is already set to \(value) — left alone"
        case .foreignUnreadable:
            return "\(ShellEnvironment.baseURLName) appears in the shell profile in a form this app "
                + "cannot read, so the profile was left alone"
        }
    }

    var isWarning: Bool {
        guard let verdict else { return true }
        switch verdict {
        case .foreign, .foreignUnreadable, .withdrawn, .unreadable:
            return true
        case .absent, .oursOutdated:
            return !wrote
        case .ours:
            return false
        }
    }
}
