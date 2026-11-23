import Foundation
import Security

extension Keychain {
    enum OwnRead: Equatable {
        case found(Data)
        case missing
        case refused(OSStatus)
    }

    private static let interactionLock = NSLock()

    static let ownItemLock = NSLock()

    static func readOwnItem(service: String, account: String) -> OwnRead {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail,
        ]
        var found: CFTypeRef?
        let status = withoutInteraction { SecItemCopyMatching(query as CFDictionary, &found) }
        switch status {
        case errSecSuccess:
            guard let data = found as? Data else { return .refused(errSecInternalError) }
            return .found(data)
        case errSecItemNotFound:
            return .missing
        default:
            return .refused(status)
        }
    }

    static func stagingName(for service: String) -> String { "Hats writing \(service)" }

    static func writeOwnItem(
        service: String,
        account: String,
        data: Data,
        remove: (String, String) throws -> Void = { try Keychain.delete(service: $0, account: $1) },
        add: ([CFString: Any]) -> OSStatus = { item in withoutInteraction { SecItemAdd(item as CFDictionary, nil) } },
        readBack: (String, String) -> OwnRead = { readOwnItem(service: $0, account: $1) },
        rename: (String, String, String) -> OSStatus = { renameOwnItem(from: $0, to: $1, account: $2) }
    ) throws {
        ownItemLock.lock()
        defer { ownItemLock.unlock() }
        let staging = stagingName(for: service)
        if readBack(service, account) == .missing,
           let recovered = recoverStagedItem(service: service, account: account, readOwn: readBack, rename: rename),
           recovered.renamed != errSecSuccess {
            throw KeychainError(
                operation: "write \(service)",
                detail: "renaming the leftover \(staging) back failed: \(message(for: recovered.renamed)); "
                    + "the value is kept under \(staging)"
            )
        }
        try remove(staging, account)
        let added = add([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: staging,
            kSecAttrAccount: account,
            kSecAttrLabel: staging,
            kSecValueData: data,
        ])
        guard added == errSecSuccess else {
            throw KeychainError(operation: "write \(service)", detail: message(for: added))
        }
        guard readBack(staging, account) == .found(data) else {
            try? remove(staging, account)
            throw KeychainError(
                operation: "write \(service)",
                detail: "the value written under \(staging) did not read back the same; the old item is kept"
            )
        }
        do { try remove(service, account) } catch {
            try? remove(staging, account)
            throw error
        }
        let renamed = rename(staging, service, account)
        guard renamed == errSecSuccess else {
            throw KeychainError(
                operation: "write \(service)",
                detail: "renaming \(staging) failed: \(message(for: renamed)); the value is kept under \(staging)"
            )
        }
    }

    static func recoverStagedItem(
        service: String,
        account: String,
        readOwn: (String, String) -> OwnRead,
        rename: (String, String, String) -> OSStatus
    ) -> (data: Data, renamed: OSStatus)? {
        let staging = stagingName(for: service)
        guard case .found(let data) = readOwn(staging, account) else { return nil }

        return (data, rename(staging, service, account))
    }

    static func renameOwnItem(from staging: String, to service: String, account: String) -> OSStatus {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: staging,
            kSecAttrAccount: account,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail,
        ]
        let changes: [CFString: Any] = [
            kSecAttrService: service,
            kSecAttrLabel: service,
        ]

        return withoutInteraction { SecItemUpdate(query as CFDictionary, changes as CFDictionary) }
    }

    static func message(for status: OSStatus) -> String {
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "\(text) (\(status))"
    }

    private static func withoutInteraction(_ body: () -> OSStatus) -> OSStatus {
        interactionLock.lock()
        defer { interactionLock.unlock() }
        var allowed: DarwinBoolean = true
        let known = SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess
        _ = SecKeychainSetUserInteractionAllowed(false)
        defer { _ = SecKeychainSetUserInteractionAllowed(known ? allowed.boolValue : true) }
        return body()
    }
}
