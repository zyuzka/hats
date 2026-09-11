import Foundation

extension AccountStore {
    func restoreLiveSlot(
        _ liveBefore: Data?,
        attempted: Data,
        target: Account,
        inSlot liveSlot: String,
        after cause: Error
    ) throws {
        let now = liveSlotNow(inSlot: liveSlot)
        let decision = RollbackDecision.decide(
            now: now,
            attempted: attempted,
            liveBefore: liveBefore
        )
        if decision != .restore {
            Journal.log("activate.rollback", [
                "target": target.email,
                "restored": "left alone",
                "slot": decision == .leaveUnreadableSlotAlone ? "unreadable" : "another login",
                "reason": cause.localizedDescription,
                "rollbackFailure": "none",
            ])
            let why = cause.localizedDescription
            throw decision == .leaveUnreadableSlotAlone
                ? SwitchError.liveSlotUnreadableDuringRollback(target.display, cause: why)
                : SwitchError.liveSlotMovedDuringRollback(target.display, cause: why)
        }
        var rollbackError: Error?
        do {
            if let liveBefore {
                _ = try writeVerified(
                    liveBefore,
                    to: liveSlot,
                    label: "the previous login"
                )
            } else {
                try deleteVerified(liveSlot, label: "the credential this switch wrote")
            }
        } catch {
            rollbackError = error
        }
        Journal.log("activate.rollback", [
            "target": target.email,
            "restored": rollbackError == nil
                ? Journal.fingerprint(liveBefore) : "failed",
            "reason": cause.localizedDescription,
            "rollbackFailure": rollbackError?.localizedDescription ?? "none",
        ])
        if let rollbackError {
            throw SwitchError.rollbackFailed(
                target.display,
                cause: cause.localizedDescription,
                rollback: rollbackError.localizedDescription)
        }
    }
    func liveSlotNow(inSlot liveSlot: String) -> LiveSlotNow {
        do {
            guard let data = try Keychain.read(service: liveSlot, account: osAccount) else {
                return .empty
            }
            return .holding(data)
        } catch {
            return .unreadable
        }
    }

    func writeVerified(
        _ data: Data,
        to service: String,
        label: String
    ) throws -> Data {
        try Keychain.write(service: service, account: osAccount, data: data)
        guard let written = try Keychain.read(service: service, account: osAccount),
              written == data else {
            throw SwitchError.writeDidNotTake(label)
        }
        return written
    }

    func deleteVerified(_ service: String, label: String) throws {
        try Keychain.delete(service: service, account: osAccount)
        guard try Keychain.read(service: service, account: osAccount) == nil else {
            throw SwitchError.deletionDidNotTake(label)
        }
    }
}
