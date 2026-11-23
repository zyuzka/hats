import Foundation
@testable import Hats

final class KeychainItemStore {
    var items: [String: Data] = [:]
    var order: [String] = []
    var added: Data?
    var addStatus: OSStatus = errSecSuccess
    var readOverride: [String: Keychain.OwnRead] = [:]
    var failRemoveOf: String?
    var renameStatus: OSStatus = errSecSuccess

    func read(_ name: String) -> Keychain.OwnRead {
        order.append("read \(name)")
        return readOverride[name] ?? items[name].map { .found($0) } ?? .missing
    }

    func remove(_ name: String) throws {
        order.append("remove \(name)")
        if name == failRemoveOf { throw KeychainError(operation: "delete \(name)", detail: "refused") }
        items[name] = nil
    }

    func add(_ item: [CFString: Any]) -> OSStatus {
        let name = item[kSecAttrService] as? String ?? "?"
        order.append("add \(name)")
        added = item[kSecValueData] as? Data
        if addStatus == errSecSuccess { items[name] = added }
        return addStatus
    }

    func rename(_ from: String, _ to: String) -> OSStatus {
        order.append("rename \(from) -> \(to)")
        guard renameStatus == errSecSuccess else { return renameStatus }
        items[to] = items.removeValue(forKey: from)

        return errSecSuccess
    }
}
