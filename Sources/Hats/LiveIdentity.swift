import Foundation

enum LiveIdentity: Equatable {
    case account(String)
    case loggedOut
    case unreadable

    init(status: CLI.Status?) {
        guard let status else {
            self = .unreadable
            return
        }
        guard status.loggedIn else {
            self = .loggedOut
            return
        }
        guard let raw = status.email, let email = Account.storableAddress(raw) else {
            self = .unreadable
            return
        }
        self = .account(email)
    }

    var email: String? {
        guard case .account(let email) = self else { return nil }
        return email
    }

    var display: String {
        switch self {
        case .account(let email):
            return email
        case .loggedOut:
            return "Not logged in"
        case .unreadable:
            return "Cannot tell who is logged in"
        }
    }

    func isASettledChange(from shown: LiveIdentity) -> Bool {
        guard case .account(let read) = self else { return false }
        guard case .account(let onScreen) = shown else { return true }
        return !Account.sameAddress(read, onScreen)
    }

    func hasLiveLoginMoved(since previous: LiveIdentity) -> Bool {
        guard case .account(let now) = self else { return false }
        switch previous {
        case .unreadable:
            return false
        case .loggedOut:
            return true
        case .account(let before):
            return !Account.sameAddress(now, before)
        }
    }
}

enum ReconcileOutcome: Equatable {
    case reconciled(account: String, changed: Bool)
    case nobodyLoggedIn
    case identityUnreadable
    case liveSlotEmpty
    case liveSlotUnreadable
    case credentialUnclaimed

    var hasObservedTheLiveLogin: Bool {
        guard case .reconciled = self else { return false }
        return true
    }

    var unsettledReason: String? {
        switch self {
        case .reconciled:
            return nil
        case .nobodyLoggedIn:
            return "nobody is logged in"
        case .identityUnreadable:
            return "claude auth status did not answer"
        case .liveSlotEmpty:
            return "the live credential slot is empty"
        case .liveSlotUnreadable:
            return "the live credential slot could not be read"
        case .credentialUnclaimed:
            return "the live login is not the one this watch is waiting for"
        }
    }
}

struct LoginWatch: Equatable {
    let expecting: String?
    let identityBefore: LiveIdentity

    func hasSettled(onReconciled account: String) -> Bool {
        guard let expecting else { return true }
        return Account.sameAddress(account, expecting)
    }

    func hasCompleted(identityNow: LiveIdentity, credentialMoved: Bool) -> Bool {
        guard let expecting else {
            return identityNow.hasLiveLoginMoved(since: identityBefore) || credentialMoved
        }
        guard case .account(let now) = identityNow,
              Account.sameAddress(now, expecting) else { return false }
        guard case .account(let before) = identityBefore,
              !Account.sameAddress(before, expecting) else { return credentialMoved }
        return true
    }
}

enum CredentialClaim: Equatable {
    case confirmedByWatch(email: String, credential: Data)
    case watchInProgress
    case noWatch

    init(
        observed identity: LiveIdentity,
        slot: LiveSlotNow,
        completed: Bool,
        credentialMoved: Bool
    ) {
        guard completed, credentialMoved,
              case .account(let email) = identity,
              case .holding(let credential) = slot else {
            self = .watchInProgress
            return
        }
        self = .confirmedByWatch(email: email, credential: credential)
    }

    func allows(account: String, credential: Data) -> Bool {
        guard case .confirmedByWatch(let email, let blob) = self else { return false }
        return Account.sameAddress(email, account) && blob == credential
    }

    static func forSync(duty: LoginWatchDuty) -> CredentialClaim {
        duty.isOnDuty ? .watchInProgress : .noWatch
    }

    var allowsAnUnclaimedMismatch: Bool {
        self == .noWatch
    }

    func allowsDiscovery(of account: String, credential: Data) -> Bool {
        switch self {
        case .noWatch:
            return true
        case .watchInProgress:
            return false
        case .confirmedByWatch:
            return allows(account: account, credential: credential)
        }
    }
}

enum WatchExpiry {
    static let graceAfterTheWindowCloses: TimeInterval = 30

    static func hasExpired(now: Date, deadline: Date, windowClosedAt: Date?) -> Bool {
        guard let windowClosedAt else { return now >= deadline }
        return now.timeIntervalSince(windowClosedAt) > graceAfterTheWindowCloses
    }
}

enum LiveSlotReading: Equatable {
    case credential(Data)
    case unsettled(ReconcileOutcome)

    init(_ now: LiveSlotNow) {
        switch now {
        case .holding(let data):
            self = .credential(data)
        case .empty:
            self = .unsettled(.liveSlotEmpty)
        case .unreadable:
            self = .unsettled(.liveSlotUnreadable)
        }
    }
}

enum LoginWatchDuty: Equatable {
    case none
    case onDuty
    case staleAndGone
    case staleButUnclear
    case orphanSignIn

    static func isTheSignInConfirmedGone(_ signInRunning: Bool?) -> Bool {
        signInRunning == false
    }

    static func hasTheSignInDiedWithoutFinishing(
        seenRunning: Bool,
        loginInFlight: Bool,
        signInRunning: Bool?
    ) -> Bool {
        seenRunning && loginInFlight && isTheSignInConfirmedGone(signInRunning)
    }

    static func of(onDuty: Int,
                   pollAlive: Int,
                   loginInFlight: Bool,
                   signInRunning: @autoclosure () -> Bool?) -> LoginWatchDuty {
        guard onDuty != 0 else {
            guard loginInFlight else { return .none }
            return isTheSignInConfirmedGone(signInRunning()) ? .none : .orphanSignIn
        }
        guard pollAlive != onDuty else { return .onDuty }
        return isTheSignInConfirmedGone(signInRunning()) ? .staleAndGone : .staleButUnclear
    }

    var isOnDuty: Bool {
        switch self {
        case .none, .staleAndGone: return false
        case .onDuty, .staleButUnclear, .orphanSignIn: return true
        }
    }

    var releasesTheWatch: Bool { self == .staleAndGone }
}

extension AccountStore {
    func liveIdentity() -> LiveIdentity { LiveIdentity(status: CLI.status()) }

    func liveEmail() -> String? { liveIdentity().email }
}
