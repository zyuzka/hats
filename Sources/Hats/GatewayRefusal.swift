import Foundation

final class GatewayRefusal {
    static let defaultSettle: TimeInterval = 35

    static let unidentifiedSession = "(unidentified)"

    private let lock = NSLock()
    private var settle: TimeInterval
    private var account: String?
    private var switchSeenAt: Date?
    private var switchedTo: String?
    private var moved: Set<String> = []
    private var movedInArrivalOrder: [String] = []
    private var refusalCount = 0
    private var clock: () -> Date

    init(
        settle: TimeInterval = GatewayRefusal.defaultSettle,
        account: String?,
        clock: @escaping () -> Date = Date.init
    ) {
        self.settle = settle
        self.account = account
        self.clock = clock
    }

    static func isASwitch(from previous: String?, to current: String?) -> Bool {
        guard let current, !current.isEmpty else { return false }
        guard let previous, !previous.isEmpty else { return false }
        return current != previous
    }

    static let sessionIdCap = 64

    static let sessionsRemembered = 256

    static func isKeepableInASessionKey(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.isASCII else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
    }

    static func sessionKey(_ session: String?) -> String {
        guard let session else { return unidentifiedSession }
        let reduced = String(session.unicodeScalars
            .map { isKeepableInASessionKey($0) ? Character($0) : "." }
            .prefix(sessionIdCap))
        guard !reduced.isEmpty else { return unidentifiedSession }
        return reduced
    }

    @discardableResult
    func hasSwitched(to current: String?) -> Bool {
        guard let current, !current.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard let previous = account, !previous.isEmpty else {
            account = current
            return false
        }
        guard Self.isASwitch(from: previous, to: current) else { return false }
        account = current
        switchedTo = current
        switchSeenAt = clock()
        moved = []
        movedInArrivalOrder = []
        return true
    }

    func shouldRefuse(path: String, credential: String, session: String?) -> Bool {
        let key = Self.sessionKey(session)
        lock.lock()
        defer { lock.unlock() }
        guard let seenAt = switchSeenAt else { return false }
        guard GatewayPaths.isInference(path), credential != GatewayCredential.none else {
            return false
        }
        guard clock().timeIntervalSince(seenAt) >= settle else { return false }
        guard !moved.contains(key) else { return false }
        remember(key)
        refusalCount += 1
        return true
    }

    private func remember(_ key: String) {
        moved.insert(key)
        movedInArrivalOrder.append(key)
        while movedInArrivalOrder.count > Self.sessionsRemembered {
            moved.remove(movedInArrivalOrder.removeFirst())
        }
    }

    var settleSeconds: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return settle
    }

    func useSettle(_ seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        settle = seconds
    }

    var refusals: Int {
        lock.lock()
        defer { lock.unlock() }
        return refusalCount
    }

    func setClockForTest(_ clock: @escaping () -> Date) {
        lock.lock()
        defer { lock.unlock() }
        self.clock = clock
    }

    struct Snapshot: Equatable {
        let account: String?
        let switchedTo: String?
        let secondsSinceSwitch: Double?
        let settling: Bool
        let sessionsMoved: Int
        let refusals: Int
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        guard let seenAt = switchSeenAt else {
            return Snapshot(
                account: account,
                switchedTo: nil,
                secondsSinceSwitch: nil,
                settling: false,
                sessionsMoved: 0,
                refusals: refusalCount
            )
        }
        let waited = clock().timeIntervalSince(seenAt)
        return Snapshot(
            account: account,
            switchedTo: switchedTo,
            secondsSinceSwitch: (waited * 10).rounded() / 10,
            settling: waited < settle,
            sessionsMoved: moved.count,
            refusals: refusalCount
        )
    }
}
