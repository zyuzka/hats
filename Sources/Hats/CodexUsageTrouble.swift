import Foundation

enum CodexUsageTrouble: Equatable {
    case notStored
    case loginUnreadable
    case loginIncomplete
    case needsLogin
    case anotherAccountLive
    case loginRefused
    case awaitingRenewal
    case busy
    case serverError(Int)
    case refused(Int)
    case unreadable
    case unreachable

    var keepsAnEarlierReading: Bool {
        switch self {
        case .notStored, .loginIncomplete, .needsLogin, .anotherAccountLive, .loginRefused: return false
        case .loginUnreadable, .awaitingRenewal, .busy, .serverError, .refused, .unreadable, .unreachable: return true
        }
    }

    var pausesTheHat: Bool {
        switch self {
        case .busy, .serverError, .unreachable: return true
        default: return false
        }
    }

    var journalLine: String {
        switch self {
        case .notStored: return "codex: no login stored"
        case .loginUnreadable: return "codex: login unreadable"
        case .loginIncomplete: return "codex: login incomplete"
        case .needsLogin: return "codex: needs signing in"
        case .anotherAccountLive: return "codex: live login of another account"
        case .loginRefused: return "codex: login not accepted"
        case .awaitingRenewal: return "codex: token expired, waiting for renewal"
        case .busy: return "codex: refused 429"
        case .serverError(let status): return "codex: server error \(status)"
        case .refused(let status): return "codex: refused \(status)"
        case .unreadable: return "codex: unreadable"
        case .unreachable: return "codex: unreachable"
        }
    }

    var short: String {
        switch self {
        case .notStored: return "no Codex login is stored for this hat"
        case .loginUnreadable: return "the stored Codex login could not be read; the keychain may be locked"
        case .loginIncomplete:
            return "the stored Codex login has no access token or account, so this hat needs signing in again"
        case .needsLogin: return "this Codex hat needs signing in again"
        case .anotherAccountLive:
            return "the live Codex login is another account's, so this hat needs signing in again"
        case .loginRefused: return "the Codex server did not accept this hat's login, so it needs signing in again"
        case .awaitingRenewal: return "the stored Codex token has expired and waits for its renewal"
        case .busy: return "the Codex server refused (429), Hats will ask again later"
        case .serverError(let status): return "Codex server error (\(status)), Hats will ask again later"
        case .refused(let status): return "the Codex server refused (\(status))"
        case .unreadable: return "the Codex server answered with something Hats cannot read"
        case .unreachable: return "no connection to the Codex server"
        }
    }

    var onTheRow: String { "limits unknown — " + short }

    func staleLine(seenAt: Date, timeZone: TimeZone = .current, now: Date = Date()) -> String {
        "\(short) — reading taken \(UsageReading.when(seenAt, sameDayAs: now, timeZone: timeZone))"
    }
}
