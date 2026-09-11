import Foundation

extension AccountStore {
    func activate(_ id: String, meters: MeterReading, targetMeters: MeterReading) throws {
        try requireReadableIndex()
        let configuration = try CLIState.configurationNow()
        guard let target = accounts.first(where: { $0.id == id }) else {
            throw SwitchError.unknownAccount(id)
        }
        guard let incoming = try Keychain.read(service: Slot.parked(id), account: osAccount) else {
            throw SwitchError.notCaptured(target.display)
        }
        let liveSlot = configuration.credentialService
        let liveBefore = try Keychain.read(service: liveSlot, account: osAccount)
        Journal.log("activate.begin", beginningOfTheSwitch(
            target: target,
            incoming: incoming,
            liveBefore: liveBefore,
            meters: meters,
            targetMeters: targetMeters
        ))

        let login = try outgoingLogin(liveBefore, target: target)
        if case .theTarget = login {
            Journal.log("activate.alreadyLive", ["target": target.email])
            try capture(into: id)
            return
        }

        let stateFile = configuration.stateFile()
        let stateFileURL = try stateFile.require()

        if let outgoing = liveBefore, case .another(let outgoingEmail) = login {
            try park(outgoing, belongingTo: outgoingEmail, statedIn: stateFile)
        }

        guard let incomingIdentity = target.identity else {
            throw CLIStateError.noIdentityStored(target.display)
        }
        let liveAfter = try rollingBackOnFailure(
            incoming: incoming,
            liveBefore: liveBefore,
            target: target,
            inSlot: liveSlot
        ) {
            try writeVerified(incoming, to: liveSlot, label: target.display)
        }
        try rollingBackOnFailure(
            incoming: incoming,
            liveBefore: liveBefore,
            target: target,
            inSlot: liveSlot
        ) {
            try CLIState.writeIdentity(incomingIdentity, to: stateFileURL)
        }

        Journal.log("activate.done", [
            "target": target.email,
            "liveNow": Journal.fingerprint(liveAfter),
            "stampSays": liveEmail() ?? "-",
        ])
        askWhoseTokenIsInTheSlot(
            expecting: target.email,
            credential: liveAfter,
            at: "activate"
        )

        try noteActivated(id, target: target)
    }

    func beginningOfTheSwitch(
        target: Account,
        incoming: Data,
        liveBefore: Data?,
        meters: MeterReading,
        targetMeters: MeterReading
    ) -> [String: String] {
        var begin = [
            "usage": meters.line,
            "usageAge": meters.age,
            "targetUsage": targetMeters.line,
            "targetUsageAge": targetMeters.age,
            "target": target.email,
            "incoming": Journal.fingerprint(incoming),
            "live": Journal.fingerprint(liveBefore),
            "activeID": String((activeID ?? "-").prefix(8)),
        ]
        if let trouble = meters.trouble { begin["usageTrouble"] = trouble }

        return begin
    }

    func park(_ outgoing: Data, belongingTo email: String, statedIn stateFile: CLIStateReading) throws {
        guard let owner = accounts.first(where: { Account.sameAddress($0.email, email) }) else {
            throw SwitchError.outgoingUnknown(email)
        }
        let identity = stateFile.url
            .flatMap { CLIState.readIdentity(at: $0) }
            .flatMap { $0.matches(email) ? $0 : nil }
        Journal.log("park.outgoing", [
            "owner": owner.email,
            "payload": Journal.fingerprint(outgoing),
            "identity": identity?.email ?? "none",
            "stateFile": stateFile.journalName,
        ])
        _ = try writeVerified(
            outgoing,
            to: Slot.parked(owner.id),
            label: "\(owner.display)'s previous login"
        )
        noteStored(owner.id, payload: CredentialPayload(raw: outgoing), identity: identity)
    }

    @discardableResult
    func rollingBackOnFailure<Result>(
        incoming: Data,
        liveBefore: Data?,
        target: Account,
        inSlot liveSlot: String,
        _ step: () throws -> Result
    ) throws -> Result {
        do {
            return try step()
        } catch {
            try restoreLiveSlot(
                liveBefore,
                attempted: incoming,
                target: target,
                inSlot: liveSlot,
                after: error
            )
            throw error
        }
    }
}
