import Foundation

struct KeychainWorld {
    var read: (String) throws -> Data?
    var write: (String, Data) throws -> Void
    var delete: (String) throws -> Void
    var parkedAccountIDs: () throws -> [String]

    static func real(osAccount: String) -> KeychainWorld {
        KeychainWorld(
            read: { try Keychain.read(service: $0, account: osAccount) },
            write: { try Keychain.write(service: $0, account: osAccount, data: $1) },
            delete: { try Keychain.delete(service: $0, account: osAccount) },
            parkedAccountIDs: { try Keychain.parkedAccountIDs(account: osAccount) }
        )
    }

    func deleteParked(id: String) throws {
        try delete(Slot.parked(id))
        try? delete(Slot.legacyParked(id))
    }

    func adoptLegacyParked(ids: [String]) {
        for id in ids { adoptLegacyParked(id: id) }
    }

    func adoptLegacyParked(id: String) {
        guard let payload = try? read(Slot.legacyParked(id)) else { return }
        if (try? read(Slot.parked(id))) != nil {
            try? delete(Slot.legacyParked(id))
            return
        }
        guard (try? write(Slot.parked(id), payload)) != nil else { return }
        try? delete(Slot.legacyParked(id))
    }
}
