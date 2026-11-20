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

    func adoptLegacyParked(ids: [String], log: (String, [String: String]) -> Void) {
        for id in ids { adoptLegacyParked(id: id, log: log) }
    }

    func adoptLegacyParked(id: String, log: (String, [String: String]) -> Void) {
        guard let payload = try? read(Slot.legacyParked(id)) else { return }
        let current: Data?
        do {
            current = try read(Slot.parked(id))
        } catch {
            log("hat.legacyAdoptionSkipped", [
                "id": id,
                "reason": error.localizedDescription,
            ])
            return
        }
        if current != nil {
            try? delete(Slot.legacyParked(id))
            return
        }
        guard (try? write(Slot.parked(id), payload)) != nil else { return }
        try? delete(Slot.legacyParked(id))
    }
}
