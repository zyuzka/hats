import Foundation

extension Keychain {
    static func read(
        service: String,
        account: String,
        readOwn: (String, String) -> OwnRead = { readOwnItem(service: $0, account: $1) },
        find: ([String]) -> Result = { run($0) },
        rename: (String, String, String) -> OSStatus = { renameOwnItem(from: $0, to: $1, account: $2) }
    ) throws -> Data? {
        guard route(for: service) == .hatsOwned else {
            return try findValue(service: service, account: account, find: find)
        }
        ownItemLock.lock()
        defer { ownItemLock.unlock() }
        switch readOwn(service, account) {
        case .found(let data): return data
        case .missing:
            return recoverStagedItem(service: service, account: account, readOwn: readOwn, rename: rename)?.data
        case .refused: return try findValue(service: service, account: account, find: find)
        }
    }

    private static func findValue(service: String, account: String, find: ([String]) -> Result) throws -> Data? {
        let result = find(["find-generic-password", "-s", service, "-a", account, "-w"])
        if result.status == 44 { return nil }
        guard result.status == 0 else {
            if result.stderr.contains("could not be found") { return nil }
            throw KeychainError(operation: "read \(service)", detail: result.stderr)
        }
        return storedValue(printed: result.stdout)
    }

    enum Route: Equatable {
        case hatsOwned
        case claudeCodeLive
    }

    static func route(for service: String) -> Route {
        Slot.hatsOwnedPrefixes.contains(where: service.hasPrefix) ? .hatsOwned : .claudeCodeLive
    }

    static func write(
        service: String,
        account: String,
        data: Data,
        own: (String, String, Data) throws -> Void = { try writeOwnItem(service: $0, account: $1, data: $2) },
        live: (String, String, Data) throws -> Void = { try writeLiveItem(service: $0, account: $1, data: $2) }
    ) throws {
        switch route(for: service) {
        case .hatsOwned: try own(service, account, data)
        case .claudeCodeLive: try live(service, account, data)
        }
    }
}
