import Foundation

struct CodexUsageSighting: Equatable {
    let reading: CodexUsageReading
    let at: Date
    let source: CodexUsageSource
}

enum CodexUsageNote: Equatable {
    case taken
    case olderThanHeld
}

struct CodexUsageRead: Equatable {
    let id: String
    let sentAt: Date
    let outcome: CodexUsageOutcome
}

enum CodexUsageStep: Equatable {
    case read(token: String, accountID: String)
    case trouble(CodexUsageTrouble)

    static func of(_ data: Data?, at now: Date) -> CodexUsageStep {
        guard let data else { return .trouble(.notStored) }
        guard let auth = CodexAuth(data: data), let parts = auth.accessAndAccount else {
            return .trouble(.loginIncomplete)
        }
        if let expiry = auth.accessExpiry, expiry <= now {
            return .trouble(auth.refreshToken == nil ? .needsLogin : .awaitingRenewal)
        }

        return .read(token: parts.accessToken, accountID: parts.accountID)
    }

    static func of(_ ticket: CodexTicket, isWorn: Bool, desk: CodexDesk) -> CodexUsageStep {
        let world = desk.world
        let data: Data?
        do {
            if isWorn {
                data = try world.home.readLive()
            } else {
                guard !ticket.needsSignIn else { return .trouble(.needsLogin) }
                data = try desk.heldOrStored(ticket)
            }
        } catch CodexError.notStoredYet {
            data = nil
        } catch {
            return .trouble(.loginUnreadable)
        }
        if isWorn, let owner = data.flatMap(CodexAuth.init(data:))?.owner, owner != ticket.owner {
            return .trouble(.anotherAccountLive)
        }

        return of(data, at: world.now())
    }
}

struct CodexUsageBook: Equatable {
    private(set) var sightings: [String: CodexUsageSighting] = [:]
    private(set) var troubles: [String: CodexUsageTrouble] = [:]
    private(set) var pause = RenewalBackoff()
    private(set) var busy: Set<String> = []

    @discardableResult
    mutating func note(_ sighting: CodexUsageSighting, for id: String) -> CodexUsageNote {
        if let held = sightings[id], held.at > sighting.at { return .olderThanHeld }
        sightings[id] = sighting
        troubles.removeValue(forKey: id)

        return .taken
    }

    mutating func record(_ outcome: CodexUsageOutcome, for id: String, sentAt: Date, every interval: TimeInterval) {
        if let held = sightings[id], held.at > sentAt { return }
        switch outcome {
        case .reading(let reading):
            note(CodexUsageSighting(reading: reading, at: sentAt, source: .wham), for: id)
            pause.succeeded(id)
            busy.remove(id)
        case .failed(let trouble):
            troubles[id] = trouble
            if trouble == .busy { busy.insert(id) }
            if trouble.pausesTheHat { pause.failed(id, at: sentAt, pollingEvery: interval) }
        }
    }

    func allowsReading(_ id: String, at now: Date) -> Bool { pause.allows(id, at: now) }

    func hasAGatewaySighting(of id: String, youngerThan age: TimeInterval, at now: Date) -> Bool {
        guard let held = sightings[id], held.source == .gateway else { return false }
        return now.timeIntervalSince(held.at) < age
    }

    mutating func keep(_ ids: Set<String>) {
        sightings = sightings.filter { ids.contains($0.key) }
        troubles = troubles.filter { ids.contains($0.key) }
        busy = busy.filter { ids.contains($0) }
        pause.keep(ids)
    }
}
