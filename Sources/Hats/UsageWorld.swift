import Foundation

struct UsageWorld {
    var liveSlot: () -> String?
    var read: (String) throws -> Data?
    var write: (String, Data) throws -> Void
    var renew: (String, [String]) -> Renewal
    var usage: (String) -> UsageFetch
    var now: () -> Date
    var log: (String, [String: String]) -> Void
    var mayRenew: (String) -> Bool = { _ in true }

    static func real(keychain: KeychainWorld) -> UsageWorld {
        UsageWorld(
            liveSlot: { (try? CLIState.configurationRemembered(world: .real))?.credentialService },
            read: keychain.read,
            write: keychain.write,
            renew: { TokenRenewal.renew(refreshToken: $0, scopes: $1) },
            usage: { UsageFetcher.fetch(token: $0) },
            now: Date.init,
            log: { Journal.log($0, $1) }
        )
    }
}
