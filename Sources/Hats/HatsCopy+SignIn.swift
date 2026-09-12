import Foundation

extension HatsCopy {
    static let signInInFlight =
        "Hats runs one sign-in at a time. Its window may be behind other windows, or on "
            + "another desktop."

    static func signingInAs(_ email: String?) -> String {
        guard let email, !email.isEmpty else { return "Signing in" }
        return "Signing in as \(email)"
    }

    static func signInStage(_ stage: SignInStage) -> String {
        switch stage {
        case .starting:
            return "Starting the sign-in\u{2026}"
        case .waitingForTheCode:
            return "Finish the sign-in in the browser. If the page shows a code, paste it here."
        case .working:
            return "Working\u{2026}"
        }
    }

    static func signInFailed(_ status: Int32) -> String {
        "The sign-in command stopped with status \(status). Nothing was stored. The full output is "
            + "in last-sign-in.log."
    }
}
