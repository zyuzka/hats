import Foundation

enum LoginBlocker: Equatable {
    case needsLogin
    case needsOneMoreLogin
    case loginExpired
    case loginRefused
}

struct Account: Codable, Identifiable, Equatable {
    let id: String
    var email: String
    var browser: BrowserChoice?
    var name: String?
    var tool: Tool?

    var hasStoredCredentials: Bool = false
    var identity: CLIIdentity?
    var refreshExpiresAt: Date?
    var accessExpiresAt: Date?
    var lastActivatedAt: Date?
    var lastLoginAt: Date?
    var authRefusedAt: Date?

    var display: String { email }

    var title: String { Self.storableName(name) ?? email }

    var wornTool: Tool { tool ?? .claudeCode }

    var isSwitchable: Bool { blocker() == nil }

    func blocker(at now: Date = Date()) -> LoginBlocker? {
        if !hasStoredCredentials { return .needsLogin }
        if identity == nil { return .needsOneMoreLogin }
        if wasRefusedSinceTheLastLogin { return .loginRefused }
        if isExpired(at: now) { return .loginExpired }
        return nil
    }

    var wasRefusedSinceTheLastLogin: Bool {
        guard let authRefusedAt else { return false }
        guard let lastLoginAt else { return true }

        return authRefusedAt > lastLoginAt
    }

    static func storableName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var needsLoginSoon: Bool {
        guard let refreshExpiresAt else { return false }
        return refreshExpiresAt.timeIntervalSinceNow < 24 * 3600
    }

    func allowsARenewalFor(_ said: String?) -> Bool {
        guard let said else { return true }

        return Account.sameAddress(said, email)
    }

    func afterARenewal(_ login: RenewedLogin) -> Account {
        var renewed = self
        renewed.accessExpiresAt = login.expiresAt
        if let refreshExpiresAt = login.refreshExpiresAt {
            renewed.refreshExpiresAt = refreshExpiresAt
        }

        return renewed
    }

    var isExpired: Bool { isExpired(at: Date()) }

    func isExpired(at now: Date) -> Bool {
        guard let refreshExpiresAt else { return false }
        return refreshExpiresAt <= now
    }

    static func == (a: Account, b: Account) -> Bool { a.id == b.id }

    static func sameAddress(_ a: String, _ b: String) -> Bool {
        normalizedAddress(a) == normalizedAddress(b)
    }

    static func normalizedAddress(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func storableAddress(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
