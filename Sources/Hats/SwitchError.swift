import Foundation

enum SwitchError: LocalizedError {
    case unknownAccount(String)
    case cliNotFound
    case notCaptured(String)
    case nothingToCapture
    case noBrowser(String)
    case cannotRemoveActive
    case cannotRemoveLast
    case identityUnknown
    case identityMismatch(expected: String, actual: String)
    case outgoingUnknown(String)
    case duplicateEmail(String)
    case indexUnreadable(String)
    case indexLost(String)
    case keychainUnlistable(String, cause: String)
    case rollbackFailed(String, cause: String, rollback: String)
    case writeDidNotTake(String)
    case notRecorded(String, cause: String)
    case credentialNotDeleted(String, cause: String)
    case liveSlotMovedDuringRollback(String, cause: String)
    case deletionDidNotTake(String)
    case blankAddress
    case liveSlotUnreadableDuringRollback(String, cause: String)

    var errorDescription: String? {
        switch self {
        case .unknownAccount(let id):
            return "no account with id \(id)"
        case .cliNotFound:
            return "the Claude Code command line tool was not found, so there is nothing to sign "
                + "in with. Install it, then try again."
        case .notCaptured(let label):
            return "\(label) has no stored credentials yet — log in as that account, then capture it"
        case .nothingToCapture:
            return "nothing in the live credential slot to capture"
        case .noBrowser(let label):
            return "\(label) needs a browser of its own before it can log in. The system default "
                + "does not count, and neither does no choice at all: a login that goes to the "
                + "default browser lands in whichever account that browser remembers. Pick a "
                + "specific browser for this account first."
        case .cannotRemoveActive:
            return "this is the account in use. Switch to another one first, then remove it."
        case .cannotRemoveLast:
            return "this is the only account left. Removing it would not sign you out, and the "
                + "next refresh would add it straight back."
        case .identityUnknown:
            return "cannot tell which account is logged in right now, so storing its credentials "
                + "could file them under the wrong name."
        case .identityMismatch(let expected, let actual):
            return "the account logged in right now is \(actual), not \(expected). Storing it "
                + "would overwrite \(expected)'s own login."
        case .outgoingUnknown(let email):
            return "\(email) is logged in right now and this app does not know that account, so "
                + "switching would overwrite its credentials with nowhere to put them. Add "
                + "\(email) first — the refresh will store what is live before anything moves."
        case .duplicateEmail(let label):
            return "\(label) is already in the list. A second row for the same address would "
                + "never be the one used."
        case .rollbackFailed(let label, let cause, let rollback):
            return "switching to \(label) failed (\(cause)), and putting the "
                + "previous login back failed too (\(rollback)). What the keychain "
                + "holds right now is unknown — the first write may or may not have "
                + "landed — so the tokens and the account name may disagree. Do not "
                + "switch again until this is sorted; logging in as \(label) writes "
                + "a matching pair and settles it."
        case .liveSlotMovedDuringRollback(let label, let cause):
            return "switching to \(label) failed (\(cause)), and the live credential slot "
                + "now holds a login that neither this switch nor the previous one wrote — "
                + "another Claude signed in or refreshed while this switch was running. It "
                + "was left alone rather than overwritten, so that login is intact and in "
                + "use. The account list and the stored account name may still say something "
                + "else; the next refresh reconciles them, and nothing needs undoing by hand."
        case .notRecorded(let what, let cause):
            return "\(what) took effect, but the account list could not be saved "
                + "(\(cause)). Nothing has been lost and nothing needs undoing; the "
                + "list catches up on the next refresh."
        case .credentialNotDeleted(let label, let cause):
            return "\(label) was removed from the account list, but its stored login "
                + "could not be deleted from the keychain (\(cause)). The account is "
                + "gone and does not come back; what is left is one credential nothing "
                + "claims, and the orphan sweep deletes it on a later refresh once "
                + "whatever blocked the deletion is gone."
        case .liveSlotUnreadableDuringRollback(let label, let cause):
            return "switching to \(label) failed (\(cause)), and the live credential slot could "
                + "not be read afterwards, so what it holds now is unknown. It was left untouched "
                + "rather than written over a login that might be newer than the one this switch "
                + "replaced. Unlock the keychain and allow access when macOS asks, then reopen; "
                + "logging in as the account you want live writes a matching pair and settles it."
        case .blankAddress:
            return "an account needs an address, and the one offered is blank. Nothing has been "
                + "added. If this came from `claude auth status` rather than from typing, the CLI "
                + "reported a login without a usable address — reopen the app once it answers "
                + "properly, since a blank row could never be switched to."
        case .deletionDidNotTake(let label):
            return "the keychain still holds \(label) after a delete that reported success, so "
                + "the live slot that had to end up empty is not empty. Nothing has been marked "
                + "active, and the credential in use belongs to a switch that failed. Check that "
                + "another tool is not writing the same keychain item, then log in as the account "
                + "you want live — that writes a matching pair and settles it."
        case .writeDidNotTake(let label):
            return "the keychain reports something other than \(label)'s credentials "
                + "after writing them, so the switch did not take. Nothing has been "
                + "marked active. Check that another tool is not writing the same "
                + "keychain item, then try again."
        case .indexLost(let path):
            return "the account list at \(path) is gone, and the keychain still holds "
                + "parked logins that nothing now claims. Nothing has been changed or "
                + "deleted, and nothing will be until the list is back — restore it "
                + "from a backup if you have one. Do not add accounts first: a new "
                + "list would know only the account you add, and every other login "
                + "would read as abandoned."
        case .keychainUnlistable(let path, let cause):
            return "the account list at \(path) is missing and the keychain cannot be "
                + "listed (\(cause)), so this app cannot tell whether parked logins "
                + "exist. Nothing has been changed or deleted. Unlock the keychain, "
                + "allow access when macOS asks, and reopen. Do not add an account "
                + "while this lasts: it would write a list knowing only that account, "
                + "and every login already parked would read as abandoned."
        case .indexUnreadable(let path):
            return "the account list at \(path) exists but cannot be read, so this app does not "
                + "know which parked credentials belong to whom. Nothing has been changed or "
                + "deleted — your logins are still in the keychain. Repair the file and "
                + "reopen. Do not delete it or move it aside: with no list at all the app "
                + "cannot tell a parked login from an abandoned one, and the keychain "
                + "entries are the only copies."
        }
    }
}
