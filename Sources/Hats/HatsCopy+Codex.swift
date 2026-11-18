import Foundation

extension HatsCopy {
    static let codexAlreadySignedInTitle = "Already signed in"
    static let codexSignInFailedTitle = "Codex sign-in failed"
    static let codexSignInBusyTitle = "A Codex sign-in is already open"
    static let codexSignInBusy = "Finish or cancel the sign-in in its window first, then start this one."
    static let codexSignInTimedOut = "Nobody finished the sign-in within 15 minutes, so Hats stopped waiting. "
        + "Nothing was stored. Try again when you are at the browser."

    static func codexAlreadySignedIn(_ title: String) -> String {
        "\(title) is the Codex account signed in right now, so its login was stored as it is. "
            + "No sign-in was needed."
    }

    static func loginLine(for hat: Account, isWorn: Bool = false, now: Date = Date()) -> String? {
        guard hat.wornTool == .codex else { return getLoginLine(for: hat, now: now) }
        guard hat.hasStoredCredentials, let expires = hat.accessExpiresAt else { return nil }
        let remaining = expires.timeIntervalSince(now)
        if remaining > 0 { return "access token valid \(humanise(remaining))" }

        return isWorn ? "access token expired" : "access token expired, renewed when parked"
    }

    static func loginAction(for hat: Account) -> String {
        guard hat.wornTool == .codex else { return hat.hasStoredCredentials ? "Log in again…" : "Log in…" }
        return hat.hasStoredCredentials ? "Sign in again…" : "Sign in…"
    }

    static func loginAnywayTitle(for hat: Account) -> String {
        hat.wornTool == .codex ? "\(hat.title) does not need a sign-in" : "\(hat.title) does not need a login"
    }

    static func loginAnywayButton(for hat: Account) -> String {
        hat.wornTool == .codex ? "Sign in anyway" : "Log in anyway"
    }

    static func loginAnywayText(for hat: Account, now: Date = Date()) -> String {
        guard hat.wornTool == .codex else { return getLoginAnywayText(for: hat, now: now) }
        let text = "Its ChatGPT login is stored and Hats keeps it renewed while it is parked, so putting it on "
            + "works without signing in. A new sign-in opens the ChatGPT page in this hat's browser and "
            + "replaces the stored login."
        guard let line = loginLine(for: hat, now: now) else { return text }

        return "Its \(line). " + text
    }

    static func codexSigningIn(_ email: String) -> String { "Signing in to Codex as \(email)" }

    static func codexSignInText(_ browser: String) -> String {
        "The ChatGPT sign-in page is open in \(browser). Sign in there; this window closes by itself "
            + "when the login reaches Hats. Closing it, or 15 minutes without an answer, stops the sign-in."
    }
}
