import CryptoKit
import Foundation

struct CLIIdentity: Codable {
    let oauthAccount: [String: AnyCodableValue]
    let userID: String?

    var email: String? {
        if case .string(let value)? = oauthAccount["emailAddress"] { return value }
        return nil
    }

    func matches(_ address: String) -> Bool {
        guard let email else { return false }
        return Account.sameAddress(email, address)
    }
}

enum AnyCodableValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AnyCodableValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([AnyCodableValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

enum CLIState {
    static let configDirVariable = "CLAUDE_CONFIG_DIR"

    static func configDir(environment: [String: String],
                          home: String) -> URL {
        let named = environment[configDirVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if named.hasPrefix("/") {
            return URL(fileURLWithPath: named).standardizedFileURL
        }
        return URL(fileURLWithPath: home).appendingPathComponent(".claude")
    }

    static let customOAuthVariable = "CLAUDE_CODE_CUSTOM_OAUTH_URL"

    static func namedFileDirectory(environment: [String: String],
                                   home: String) -> URL {
        let named = environment[configDirVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if named.hasPrefix("/") {
            return URL(fileURLWithPath: named).standardizedFileURL
        }
        return URL(fileURLWithPath: home)
    }

    static let secureStorageDirVariable = "CLAUDE_SECURESTORAGE_CONFIG_DIR"

    static func oauthSuffix(environment: [String: String]) -> String {
        let custom = environment[customOAuthVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? "" : "-custom-oauth"
    }

    static func namedFile(environment: [String: String]) -> String {
        ".claude\(oauthSuffix(environment: environment)).json"
    }

    static func credentialHashSuffix(environment: [String: String]) -> String {
        let hashed: String
        if let secureStorage = environment[secureStorageDirVariable] {
            let named = secureStorage.trimmingCharacters(in: .whitespacesAndNewlines)
            if named.isEmpty { return "" }
            hashed = named
        } else {
            let configured = environment[configDirVariable]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard configured.hasPrefix("/") else { return "" }
            hashed = configured
        }
        let digest = SHA256.hash(data: Data(hashed.precomposedStringWithCanonicalMapping.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "-\(hex.prefix(8))"
    }

    static func credentialService(environment: [String: String]) -> String {
        "Claude Code"
            + oauthSuffix(environment: environment)
            + "-credentials"
            + credentialHashSuffix(environment: environment)
    }

    static func stateFilesInOrder(environment: [String: String],
                                  home: String) -> [URL] {
        [
            configDir(environment: environment, home: home)
                .appendingPathComponent(".config.json"),
            namedFileDirectory(environment: environment, home: home)
                .appendingPathComponent(namedFile(environment: environment)),
        ]
    }

    static func stateFile(environment: [String: String],
                          home: String,
                          exists: (URL) -> Bool) -> CLIStateFile {
        let inOrder = stateFilesInOrder(environment: environment, home: home)
        guard let read = inOrder.first(where: exists) else { return .missing(inOrder) }
        return .resolved(read)
    }

    static let configKeys: Set<String> = [configDirVariable, customOAuthVariable, secureStorageDirVariable]

    static func configuration(from environment: [String: String]) -> [String: String] {
        var kept: [String: String] = [:]
        for key in configKeys {
            let value = environment[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty { kept[key] = value }
        }
        return kept
    }

    static func configurations(
        of pids: [Int32],
        trusting isTrusted: (Int32) -> Bool? = TrustedCLI.isTheRealCLI,
        reading: (Int32) -> ProcessEnvironmentRead
    ) -> [[String: String]]? {
        var distinct: [[String: String]] = []
        for pid in pids {
            guard let trusted = isTrusted(pid) else { return nil }
            guard trusted else { continue }
            switch reading(pid) {
            case .processGone:
                continue
            case .unreadable:
                return nil
            case .read(let environment):
                let kept = configuration(from: environment)
                if !distinct.contains(kept) { distinct.append(kept) }
            }
        }
        return distinct
    }

    static func configurationInForce(
        liveConfigurations: [[String: String]],
        own: [String: String]
    ) -> (configuration: [String: String], source: ConfigEnvironmentSource)? {
        if liveConfigurations.count > 1 { return nil }
        if let only = liveConfigurations.first { return (only, .liveCLI) }
        return (configuration(from: own), .ourOwn)
    }

    static var configurationTTL: TimeInterval = 30

    private static let remembered = RememberedCLIConfigurations()

    static func forgetTheCLIConfiguration() {
        remembered.forget()
    }

    static func swept(_ sessions: [Session]?) -> [[String: String]]? {
        guard let sessions else { return nil }
        guard let found = configurations(of: sessions.map(\.pid), reading: {
            ProcessEnvironment.read(pid: $0, keeping: configKeys)
        }) else { return nil }
        remembered.keep(found)
        return found
    }

    private static func sweptNow() -> [[String: String]]? {
        swept(SessionDiscovery.everySessionThatHoldsAPort())
    }

    private static func sweptRecently() -> [[String: String]]? {
        swept(SessionDiscovery.everySessionSeenRecently())
    }

    static func configurationNow() throws -> CLIConfiguration {
        try configuration(liveConfigurations: sweptNow(),
                          own: ProcessInfo.processInfo.environment,
                          home: NSHomeDirectory())
    }

    static func configurationRemembered() throws -> CLIConfiguration {
        try configuration(
            liveConfigurations: remembered.value(within: .seconds(configurationTTL)) ?? sweptRecently(),
            own: ProcessInfo.processInfo.environment,
            home: NSHomeDirectory()
        )
    }

    static func configuration(liveConfigurations: [[String: String]]?,
                              own: [String: String],
                              home: String) throws -> CLIConfiguration {
        guard let liveConfigurations else { throw CLIStateError.liveSessionsUnreadable }
        guard let inForce = configurationInForce(liveConfigurations: liveConfigurations, own: own)
        else {
            throw CLIStateError.liveCLIsDisagree(
                liveConfigurations.map { configDir(environment: $0, home: home).path }.sorted()
            )
        }
        return CLIConfiguration(variables: inForce.configuration,
                                source: inForce.source,
                                home: home)
    }

    static func readIdentity(at url: URL) -> CLIIdentity? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any],
              let accountData = try? JSONSerialization.data(withJSONObject: account),
              let decoded = try? JSONDecoder().decode([String: AnyCodableValue].self, from: accountData)
        else { return nil }

        return CLIIdentity(oauthAccount: decoded, userID: root["userID"] as? String)
    }

    static let accountScopedCacheKeys = [
        "cachedUsageUtilization",
        "cachedExtraUsageDisabledReason",
        "claudeMaxTier",
        "hasAvailableSubscription",
        "hasAvailableMaxSubscription",
        "recommendedSubscription",
        "orgModelDefaultCache",
        "penguinModeOrgEnabled",
        "modelAccessCache",
        "isQualifiedForDataSharing",
        "additionalModelCostsCache",
        "additionalModelOptionsCache",
        "hasOpusPlanDefault",
        "claudeCodeFirstTokenDate",
        "claudeAiMcpEverConnected",
        "subscriptionNoticeCount",
        "maxSubscriptionNoticeCount",
        "subscriptionUpsellShownCount",
    ]

    static func writeIdentity(_ identity: CLIIdentity, to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        let data = try Data(contentsOf: target)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIStateError.unreadable(target.path)
        }

        let accountData = try JSONEncoder().encode(identity.oauthAccount)
        guard let account = try JSONSerialization.jsonObject(with: accountData) as? [String: Any] else {
            throw CLIStateError.unreadable(target.path)
        }
        root["oauthAccount"] = account
        if let userID = identity.userID {
            root["userID"] = userID
        } else {
            root.removeValue(forKey: "userID")
        }
        for key in accountScopedCacheKeys { root.removeValue(forKey: key) }

        let updated = try JSONSerialization.data(withJSONObject: root, options: [])
        let temp = target.appendingPathExtension("hats-tmp")
        try updated.write(to: temp)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
    }
}

typealias RememberedCLIConfigurations = RememberedFor<[[String: String]]>

enum ConfigEnvironmentSource: Equatable {
    case liveCLI
    case ourOwn

    var journalName: String {
        switch self {
        case .liveCLI: return "fromTheCLI"
        case .ourOwn: return "fromOurOwn"
        }
    }
}

struct CLIConfiguration: Equatable {
    let variables: [String: String]
    let source: ConfigEnvironmentSource
    let home: String

    var credentialService: String {
        CLIState.credentialService(environment: variables)
    }

    func stateFile(exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
    -> CLIStateReading {
        CLIStateReading(
            file: CLIState.stateFile(environment: variables, home: home, exists: exists),
            source: source
        )
    }
}

struct CLIStateReading: Equatable {
    let file: CLIStateFile
    let source: ConfigEnvironmentSource

    var url: URL? { file.url }

    func require() throws -> URL { try file.require() }

    var journalName: String { "\(file.journalName)/\(source.journalName)" }
}

enum CLIStateFile: Equatable {
    case resolved(URL)
    case missing([URL])
    case disagreeing([String])

    var url: URL? {
        guard case .resolved(let url) = self else { return nil }
        return url
    }

    var journalName: String {
        switch self {
        case .resolved: return "resolved"
        case .missing: return "missing"
        case .disagreeing: return "disagreeing"
        }
    }

    func require() throws -> URL {
        switch self {
        case .resolved(let url):
            return url
        case .missing(let candidates):
            throw CLIStateError.stateFileNotFound(candidates.map(\.path))
        case .disagreeing(let homes):
            throw CLIStateError.liveCLIsDisagree(homes)
        }
    }
}

enum CLIStateError: LocalizedError {
    case unreadable(String)
    case stateFileNotFound([String])
    case liveCLIsDisagree([String])
    case liveSessionsUnreadable
    case noIdentityStored(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            return "\(path) could not be read as JSON"
        case .stateFileNotFound(let candidates):
            return "the CLI's account file was not found, so there is nothing to write the "
                + "identity into. Looked for: \(candidates.joined(separator: ", ")). "
                + "If \(CLIState.configDirVariable) names the configuration home, it has to "
                + "be set in "
                + "the shell this app was started from."
        case .liveCLIsDisagree(let homes):
            return "the Claude Code sessions running now do not read the same account file — their "
                + "configuration homes are \(homes.joined(separator: ", ")) — so no single file is "
                + "the right one to write. Quit the sessions that do not belong to the "
                + "\(CLIState.configDirVariable) you work with, then try again."
        case .liveSessionsUnreadable:
            return "the list of Claude Code sessions running now could not be read, so there is no "
                + "way to tell which account file they read — and switching against the wrong one "
                + "would leave a running session on the previous account. Try again in a moment; if "
                + "it keeps failing, the operations log carries the reason under processTable."
        case .noIdentityStored(let label):
            return "\(label) has credentials but no stored account identity — log in as it once "
                + "more so both halves get captured together."
        }
    }
}
