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

    static func writeOwnItem(
        service: String,
        account: String,
        data: Data,
        remove: ([String]) -> Result = { run($0) },
        add: ([CFString: Any]) -> OSStatus = { item in withoutInteraction { SecItemAdd(item as CFDictionary, nil) } }
    ) throws {
        ownItemLock.lock()
        defer { ownItemLock.unlock() }
        let removed = remove(["delete-generic-password", "-s", service, "-a", account])
        guard removed.status == 0 || removed.status == 44 else {
            throw KeychainError(operation: "write \(service)", detail: removed.stderr)
        }
        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrLabel: service,
            kSecValueData: data,
        ]
        let status = add(item)
        guard status == errSecSuccess else {
            throw KeychainError(operation: "write \(service)", detail: message(for: status))
        }
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
