import Foundation

struct GatewaySessionRow: Equatable, Identifiable {
    let session: String

    var id: String { session }

    var requests: Int
    var lastStatus: Int
    var lastSeen: ContinuousClock.Instant
    var credential: String
}

enum GatewaySessions {
    static let kept = 32

    static func noting(
        _ rows: [String: GatewaySessionRow],
        session: String,
        credential: String,
        status: Int,
        at now: ContinuousClock.Instant,
        countingANewRequest: Bool = true,
        kept: Int = kept
    ) -> [String: GatewaySessionRow] {
        var rows = rows
        if var row = rows[session] {
            if countingANewRequest { row.requests += 1 }
            if now >= row.lastSeen {
                row.lastStatus = status
                row.lastSeen = now
                row.credential = credential
            }
            rows[session] = row
            return rows
        }
        rows[session] = GatewaySessionRow(
            session: session,
            requests: 1,
            lastStatus: status,
            lastSeen: now,
            credential: credential
        )
        return evicting(rows, kept: kept)
    }

    static func evicting(_ rows: [String: GatewaySessionRow], kept: Int) -> [String: GatewaySessionRow] {
        var rows = rows
        while rows.count > kept, let oldest = rows.values.min(by: isSeenBefore) {
            rows.removeValue(forKey: oldest.session)
        }
        return rows
    }

    static func secondsBetween(_ earlier: ContinuousClock.Instant,
                               _ later: ContinuousClock.Instant) -> Double {
        let elapsed = earlier.duration(to: later)
        return Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
    }

    static func merged(
        _ tables: [[String: GatewaySessionRow]],
        kept: Int = kept
    ) -> [GatewaySessionRow] {
        let all = tables.reduce(into: [String: GatewaySessionRow]()) { all, rows in
            for (session, row) in rows {
                guard let mine = all[session] else { all[session] = row; continue }
                all[session] = isSeenBefore(mine, row) ? row : mine
            }
        }
        return evicting(all, kept: kept).values.sorted { isSeenBefore($1, $0) }
    }

    static func isSeenBefore(_ a: GatewaySessionRow, _ b: GatewaySessionRow) -> Bool {
        if a.lastSeen != b.lastSeen { return a.lastSeen < b.lastSeen }
        return a.session < b.session
    }

    static func reported(_ rows: [String: GatewaySessionRow],
                         now: ContinuousClock.Instant) -> [[String: Any]] {
        rows.values
            .sorted { isSeenBefore($1, $0) }
            .map { row in
                [
                    "session": HatsCopy.shortSession(row.session),
                    "requests": row.requests,
                    "last_status": row.lastStatus,
                    "credential": row.credential,
                    "seconds_since_last": (secondsBetween(row.lastSeen, now) * 10).rounded() / 10,
                ]
            }
    }
}
