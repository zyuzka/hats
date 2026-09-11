import Foundation

final class GatewayLedger {
    private let lock = NSLock()
    private let started = Date()
    private var requests = 0
    private var failures = 0
    private var byCredential: [String: Int] = [:]
    private var bySession: [String: GatewaySessionRow] = [:]
    private var refusedTargets = 0
    private var lastStatus = 0
    private var lastPath = ""

    private func record(
        path: String,
        credential: String,
        status: Int,
        session: String?,
        at now: ContinuousClock.Instant,
        countingANewRequest: Bool = true
    ) {
        bySession = GatewaySessions.noting(
            bySession,
            session: GatewayRefusal.sessionKey(session),
            credential: credential,
            status: status,
            at: now,
            countingANewRequest: countingANewRequest
        )
        lastStatus = status
        lastPath = path
    }

    func note(path: String, credential: String, status: Int, session: String?, at now: ContinuousClock.Instant = .now) {
        lock.lock()
        defer { lock.unlock() }
        requests += 1
        byCredential[credential, default: 0] += 1
        record(path: path, credential: credential, status: status, session: session, at: now)
        if status == 0 { failures += 1 }
    }

    func noteTruncated(path: String, credential: String, session: String?, at now: ContinuousClock.Instant = .now) {
        lock.lock()
        defer { lock.unlock() }
        failures += 1
        record(
            path: path,
            credential: credential,
            status: 0,
            session: session,
            at: now,
            countingANewRequest: false
        )
    }

    func noteRefusedTarget(path: String, credential: String, session: String?, at now: ContinuousClock.Instant = .now) {
        lock.lock()
        defer { lock.unlock() }
        requests += 1
        byCredential[credential, default: 0] += 1
        refusedTargets += 1
        record(path: path, credential: credential, status: 502, session: session, at: now)
    }

    func snapshot() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return [
            "uptime_seconds": (Date().timeIntervalSince(started) * 10).rounded() / 10,
            "requests": requests,
            "upstream_failures": failures,
            "refused_targets": refusedTargets,
            "credentials_seen": byCredential,
            "sessions_seen": bySession.count,
            "sessions": GatewaySessions.reported(bySession, now: .now),
            "last_status": lastStatus,
            "last_path": lastPath,
        ]
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    var failureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return failures
    }

    var sessionRows: [String: GatewaySessionRow] {
        lock.lock()
        defer { lock.unlock() }
        return bySession
    }

    var refusedTargetCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return refusedTargets
    }
}
