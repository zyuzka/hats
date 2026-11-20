import Foundation

struct CodexGatewayLogin: Equatable {
    let hatID: String
    let accessToken: String
    let accountID: String
    let shift: Int

    static func of(hatID: String, auth data: Data) -> (accessToken: String, accountID: String)? {
        CodexAuth(data: data)?.accessAndAccount
    }
}

final class CodexGatewayState: @unchecked Sendable {
    static let turnStatesKept = 512
    static let threadAtRiskFor: TimeInterval = 6 * 3600

    private let lock = NSLock()
    private var worn: CodexGatewayLogin?
    private var shifts = 0
    private var turnStates: [String: String] = [:]
    private var turnStateOrder: [String] = []
    private var threads: [String: Date] = [:]
    private var readings: [String: CodexUsageSighting] = [:]
    private var readingSink: ((String, CodexUsageSighting) -> Void)?

    var login: CodexGatewayLogin? { locked { worn } }

    @discardableResult
    func wear(hatID: String, auth data: Data) -> CodexGatewayLogin? {
        guard let parts = CodexGatewayLogin.of(hatID: hatID, auth: data) else { return nil }
        return locked {
            if worn?.hatID != hatID { shifts += 1 }
            let login = CodexGatewayLogin(
                hatID: hatID,
                accessToken: parts.accessToken,
                accountID: parts.accountID,
                shift: shifts
            )
            worn = login
            return login
        }
    }

    func takeOff() {
        locked {
            if worn != nil { shifts += 1 }
            worn = nil
        }
    }

    func noteTurnState(_ value: String, issuedUnder hatID: String) {
        locked {
            if turnStates[value] == nil { turnStateOrder.append(value) }
            turnStates[value] = hatID
            while turnStateOrder.count > Self.turnStatesKept {
                turnStates.removeValue(forKey: turnStateOrder.removeFirst())
            }
        }
    }

    func isTurnState(_ value: String, issuedUnder hatID: String) -> Bool {
        locked { turnStates[value] == hatID }
    }

    func noteThread(_ id: String, at now: Date = Date()) {
        locked { threads[id] = now }
    }

    var threadIDs: [String] { threadsAtRisk(at: Date()) }

    func threadsAtRisk(at now: Date) -> [String] {
        let aged: [String] = locked {
            let old = threads.filter { now.timeIntervalSince($0.value) > Self.threadAtRiskFor }.map(\.key)
            for id in old { threads.removeValue(forKey: id) }
            return old
        }
        for id in aged.sorted() { Journal.log("codexGateway.threadAged", ["thread": id]) }
        return locked { threads.keys.sorted() }
    }

    func forgetThreads() {
        locked { threads.removeAll() }
    }

    var onReading: ((String, CodexUsageSighting) -> Void)? {
        get { locked { readingSink } }
        set { locked { readingSink = newValue } }
    }

    func noteReading(_ reading: CodexUsageReading, for hatID: String, at now: Date = Date()) {
        let sighting = CodexUsageSighting(reading: reading, at: now, source: .gateway)
        let sink: ((String, CodexUsageSighting) -> Void)? = locked {
            readings[hatID] = sighting
            return readingSink
        }
        sink?(hatID, sighting)
    }

    func reading(for hatID: String) -> CodexUsageReading? { locked { readings[hatID]?.reading } }

    func sighting(for hatID: String) -> CodexUsageSighting? { locked { readings[hatID] } }

    private func locked<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
