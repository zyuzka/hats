import Foundation

extension AccountStore {
    var claudeHats: [Account] { accounts.filter(\.isClaude) }

    var codexHats: [Account] { accounts.filter { $0.wornTool == .codex } }

    func remove(_ id: String) throws {
        try requireReadableIndex()
        guard id != activeID, id != codexActiveID else { throw SwitchError.cannotRemoveActive }
        let hat = accounts.first(where: { $0.id == id })
        let sameProvider = accounts.filter { $0.wornTool == (hat?.wornTool ?? .claudeCode) }
        guard sameProvider.count > 1 else { throw SwitchError.cannotRemoveLast }
        let slot = hat?.wornTool == .codex ? Slot.codexParked(id) : Slot.parked(id)
        let payload: Data? = try? keychain.read(slot)
        let display = hat?.display ?? id
        try commit { accounts, _ in accounts.removeAll { $0.id == id } }
        var deletionError: Error?
        do {
            if hat?.wornTool == .codex {
                try keychain.delete(slot)
            } else {
                try keychain.deleteParked(id: id)
            }
        } catch {
            deletionError = error
        }
        Journal.log("remove", [
            "id": String(id.prefix(8)),
            "payload": Journal.fingerprint(payload),
            "credentialDeleted": deletionError == nil ? "true" : "failed",
            "deletionFailure": deletionError?.localizedDescription ?? "none",
        ])
        if let deletionError {
            throw SwitchError.credentialNotDeleted(display, cause: deletionError.localizedDescription)
        }
    }

    func update(_ account: Account) throws {
        try requireReadableIndex()
        guard accounts.contains(account) else { return }
        try commit { accounts, _ in
            guard let index = accounts.firstIndex(of: account) else { return }
            accounts[index] = account
        }
    }
}
