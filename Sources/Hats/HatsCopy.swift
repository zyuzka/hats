import Foundation

enum HatsCopy {
    static func blocker(for hat: Account, now: Date = Date()) -> String? {
        switch hat.blocker(at: now) {
        case .none: return nil
        case .needsLogin: return "needs login"
        case .needsOneMoreLogin: return "needs one more login"
        case .loginExpired: return "login expired"
        case .loginRefused: return "login refused — needs logging in again"
        }
    }

    static func cannotWear(_ blocker: String) -> String { "Cannot wear this hat — \(blocker)" }

    static func expiry(for hat: Account, now: Date = Date()) -> String? {
        guard let expires = hat.refreshExpiresAt else { return nil }
        let remaining = expires.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        guard remaining < 24 * 3600 else { return nil }
        return "expires in \(humanise(remaining))"
    }

    static func loginValidity(for hat: Account, now: Date = Date()) -> String? {
        guard let expires = hat.refreshExpiresAt else { return nil }
        let remaining = expires.timeIntervalSince(now)
        return remaining > 0 ? "valid \(humanise(remaining))" : "expired"
    }

    static func usageLine(_ reading: UsageReading, timeZone: TimeZone = .current, now: Date = Date()) -> String {
        var parts: [String] = []
        if let session = reading.session {
            var line = "\(session.percent)% of 5h"
            if let resets = session.resetsAt, resets > now {
                line += " · resets \(UsageReading.clock(resets, timeZone: timeZone))"
            }
            parts.append(line)
        }
        if let weekly = reading.weekly { parts.append("week \(weekly.percent)%") }
        return parts.joined(separator: " · ")
    }

    static func staleReading(_ trouble: UsageTrouble?) -> String? {
        guard let trouble, trouble.keepsAnEarlierReading else { return nil }
        return "latest check failed — \(trouble.journalLine)"
    }

    static func parkedUsage(
        _ reading: UsageReading,
        rose: Int? = nil,
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) -> String? {
        guard let session = reading.session else { return nil }
        var parts = ["\(session.percent)%"]
        if let resets = session.resetsAt, resets > now {
            parts.append("resets \(UsageReading.clock(resets, timeZone: timeZone))")
        }
        if let rose, rose > 0 {
            parts.append("up \(rose) while not being worn")
        }
        return parts.joined(separator: " · ")
    }

    static func handover(to title: String) -> String { "at the limit → \(title)" }

    static func sessions(count: Int?, wearing: String?) -> String {
        guard let count else { return "Live sessions unknown — the process table could not be read" }
        guard count > 0 else { return "No live sessions" }
        return "\(count) live session\(count == 1 ? "" : "s") — \(keep(wearing, plural: count != 1))"
    }

    static func sessions(
        _ state: SessionsState,
        wearing: String?,
        gatewayBaseURLs: [String],
        serving: Bool
    ) -> String {
        guard case .counted(let live) = state, !live.isEmpty else {
            return sessions(count: state.count, wearing: wearing)
        }
        let through = live.filter { $0.route.isThrough(anyOf: gatewayBaseURLs) }.count
        let noun = "\(live.count) live session\(live.count == 1 ? "" : "s")"
        let via = serving ? "through the gateway" : "pointed at the gateway, which is off"
        if live.count == 1 {
            return through == 1
                ? "\(noun) — \(via)"
                : "\(noun) — not through the gateway, \(keep(wearing, plural: false))"
        }
        if through == live.count { return "\(noun) — all \(via)" }
        if through == 0 { return "\(noun) — none through the gateway, \(keep(wearing, plural: true))" }
        return "\(noun) — \(through) \(via), \(live.count - through) not"
    }

    static func shortSession(_ session: String) -> String {
        session == GatewayRefusal.unidentifiedSession ? "unidentified" : String(session.prefix(8))
    }

    static func relaySessions(_ rows: [GatewaySessionRow], serving: Bool) -> String {
        guard serving else { return "The relay is off, so it is seeing nothing" }
        guard !rows.isEmpty else { return "The relay has served no session yet" }
        let noun = rows.count >= GatewaySessions.kept
            ? "the \(rows.count) most recent sessions"
            : "\(rows.count) session\(rows.count == 1 ? "" : "s")"
        let credentials = Set(rows.map(\.credential)).count
        guard credentials > 1 else {
            return rows.count > 1
                ? "\(noun) through the relay, all on one credential"
                : "\(noun) through the relay"
        }
        return "\(noun) through the relay on \(credentials) credentials"
    }

    static let theTwoSessionListsDiffer =
        "The table above is every Claude Code process alive now, relay or not. This one is the "
            + "\(GatewaySessions.kept) most recently seen sessions the relay has served, including "
            + "sessions that have since ended; older ones are dropped. They are different questions "
            + "and need not agree."

    static func releaseNotesMissing(running: String) -> String {
        "This build reports \(running) and no release notes could be read out of it — the file is "
            + "missing, unreadable, or carries no version heading. A build packaged by package.sh "
            + "carries them, so ask for one rather than trusting the number."
    }

    static func quitCost(_ state: SessionsState) -> String? {
        let ending = "Quitting stops the gateway. A Claude Code session running through it cannot "
            + "reach Claude until Hats is running again, or until you unset the gateway variables in "
            + "that session's shell and start the session again."
        switch state {
        case .unknown:
            return "The process table could not be read, so Hats cannot say what is running. \(ending)"
        case .counted(let live) where live.isEmpty:
            return nil
        case .counted(let live):
            return "\(live.count) live session\(live.count == 1 ? "" : "s") running. \(ending)"
        }
    }

    private static func keep(_ wearing: String?, plural: Bool) -> String {
        let who = plural ? "they keep" : "it keeps"
        return wearing.map { "\(who) \($0) for now" } ?? "\(who) the current account for now"
    }

    static func banner(_ record: AutoSwitchRecord, fromTitle: String, timeZone: TimeZone = .current) -> String {
        let at = UsageReading.clock(record.firedAt, timeZone: timeZone)
        var line = "Switched automatically at \(at) — \(fromTitle) reached its \(record.limit.displayName)"
        if let resets = record.resetsAt {
            line += " · it comes back " + UsageReading.when(resets, sameDayAs: record.firedAt, timeZone: timeZone)
        }
        return line
    }

    static func humanise(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "expired" }
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        if days > 0 { return "\(days)d \(hours)h" }
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
