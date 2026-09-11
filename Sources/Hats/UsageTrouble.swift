import Foundation

enum UsageTrouble: Equatable {
    case nothingStored
    case credentialUnreadable
    case noTokenStored
    case tokenExpired
    case parkedNeedsLogin
    case renewalFailed(String)
    case fetchFailed(String)
    case liveSlotUnknown

    var keepsAnEarlierReading: Bool {
        switch self {
        case .fetchFailed, .renewalFailed:
            return true
        case .nothingStored, .credentialUnreadable, .noTokenStored, .tokenExpired,
             .parkedNeedsLogin, .liveSlotUnknown:
            return false
        }
    }

    var journalLine: String {
        switch self {
        case .nothingStored: return "no credential"
        case .credentialUnreadable: return "credential unreadable"
        case .noTokenStored: return "no token in the credential"
        case .tokenExpired: return "no usable token"
        case .parkedNeedsLogin: return "parked login cannot be renewed"
        case .renewalFailed(let reason): return "renewal \(reason)"
        case .fetchFailed(let reason): return reason
        case .liveSlotUnknown: return "which account file the CLI reads cannot be told"
        }
    }

    var onTheRow: String {
        switch self {
        case .nothingStored:
            return "limits unknown — nothing is stored for this hat yet"
        case .credentialUnreadable:
            return "limits unknown — the credential is stored but could not be read; the keychain may be locked"
        case .noTokenStored:
            return "limits unknown — the stored credential carries no token, so this hat needs logging in again"
        case .tokenExpired:
            return "limits unknown — the stored token has expired, and Claude Code renews it on its next request"
        case .parkedNeedsLogin:
            return "limits unknown — the login stored for this hat can no longer be renewed, so this "
                + "hat needs signing in again"
        case .renewalFailed(let reason):
            return "limits unknown — the parked login could not be renewed: \(reason)"
        case .fetchFailed(let reason):
            return "limits unknown — \(reason)"
        case .liveSlotUnknown:
            return "limits unknown — which account file Claude Code reads cannot be told, so "
                + "there is no telling which credential to measure"
        }
    }
}
