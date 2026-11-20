import Foundation

enum CodexError: LocalizedError, Equatable {
    case portsTaken([Int])
    case listenerFailed(String)
    case noBrowser(String)
    case browserNotOpened(String)
    case wrongAccount(expected: String, actual: String)
    case notTheSameOwner(String)
    case noOwner
    case notChatGPT
    case duplicateOwner(String)
    case notStoredYet(String)
    case notStoredInAFile(String)
    case liveUnusable(String)
    case liveUnreadable(String)
    case foreignLogin(String)
    case lockTimedOut(String)
    case writeFailed(String)
    case rolledBack(String)
    case rollbackFailed(cause: String, rollback: String)
    case leftAlone(String)
    case notACodexHat(String)
    case liveMoved(String)

    var errorDescription: String? {
        switch self {
        case .portsTaken(let ports):
            return "the sign-in needs one of the ports \(ports.map(String.init).joined(separator: " or ")) "
                + "on this Mac, and both are busy — probably a codex login is running. Finish or stop it, "
                + "then try again."
        case .listenerFailed(let why):
            return "the sign-in could not listen for the answer: \(why)"
        case .noBrowser(let hat):
            return "\(hat) needs a browser of its own before it can sign in to Codex"
        case .browserNotOpened(let why):
            return "the hat's browser did not open: \(why)"
        case .wrongAccount(let expected, let actual):
            return "this hat is \(expected), but the sign-in was \(actual). Nothing was stored. "
                + "Sign in as \(expected) in this hat's browser."
        case .notTheSameOwner(let hat):
            return "the sign-in belongs to another ChatGPT account than \(hat). Nothing was stored."
        case .noOwner:
            return "the login names no ChatGPT user and account, so Hats cannot tell whose it is. Nothing was stored."
        case .notChatGPT:
            return "the login is not a ChatGPT sign-in. Nothing was stored."
        case .duplicateOwner(let hat):
            return "this Codex account is already the hat \(hat)"
        case .notStoredYet(let hat):
            return "\(hat) has no stored Codex login yet — sign in first"
        case .notStoredInAFile(let why):
            return "Codex keeps its login somewhere Hats does not change (\(why)). Nothing was written."
        case .liveUnusable(let why):
            return "~/.codex/auth.json cannot be replaced safely: \(why). Nothing was written."
        case .liveUnreadable(let why):
            return "~/.codex/auth.json could not be read: \(why). Nothing was written."
        case .foreignLogin(let who):
            return "Codex is signed in as \(who), which is not one of your hats. Add it as a hat first, "
                + "so its login is kept; nothing was written."
        case .lockTimedOut(let lock):
            return "Codex kept \(lock) locked; nothing was written. Try again in a moment."
        case .writeFailed(let why):
            return "the new login could not be written to ~/.codex/auth.json: \(why)"
        case .rolledBack(let why):
            return "the new login did not take (\(why)); the previous login was put back"
        case .rollbackFailed(let cause, let rollback):
            return "the new login did not take (\(cause)), and putting the previous one back failed too "
                + "(\(rollback)). Check ~/.codex/auth.json."
        case .leftAlone(let why):
            return "the new login did not take (\(why)), and something else changed ~/.codex/auth.json "
                + "meanwhile, so Hats left it as it is"
        case .notACodexHat(let id):
            return "no Codex hat with id \(id)"
        case .liveMoved(let account):
            return "Codex was signed in to another account (\(account)) meanwhile, so Hats left "
                + "~/.codex/auth.json as it is"
        }
    }
}
