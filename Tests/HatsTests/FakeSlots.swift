import Foundation
@testable import Hats

final class FakeSlots {
    static let live = "Claude Code-credentials"
    var contents: [String: Data]
    var readFailures: Set<String> = []
    var failReadsAfter: Int?
    var writeFailures: Set<String> = []
    var renewals: [(refreshToken: String, scopes: [String])] = []
    var writes: [(service: String, data: Data)] = []
    var usedTokens: [String] = []
    var answer: Renewal = .failed("no answer staged")
    var movesTo: [String: Data] = [:]
    var swallowsWrites = false
    var logged: [(operation: String, details: [String: String])] = []
    private var readCounts: [String: Int] = [:]

    init(_ contents: [String: Data]) { self.contents = contents }

    func world(now: Date, liveSlot: String? = FakeSlots.live) -> UsageWorld {
        UsageWorld(
            liveSlot: { liveSlot },
            read: { [unowned self] service in
                if self.readFailures.contains(service) {
                    throw KeychainError(operation: "read \(service)", detail: "interaction not allowed")
                }
                self.readCounts[service, default: 0] += 1
                if let after = self.failReadsAfter, self.readCounts[service, default: 0] > after {
                    throw KeychainError(operation: "read \(service)", detail: "interaction not allowed")
                }
                if self.readCounts[service] == 2, let moved = self.movesTo[service] { return moved }

                return self.contents[service]
            },
            write: { [unowned self] service, data in
                self.writes.append((service, data))
                if self.writeFailures.contains(service) {
                    throw KeychainError(operation: "write \(service)", detail: "the keychain is locked")
                }
                guard !self.swallowsWrites else { return }
                self.contents[service] = data
            },
            renew: { [unowned self] refreshToken, scopes in
                self.renewals.append((refreshToken, scopes))

                return self.answer
            },
            usage: { [unowned self] token in
                self.usedTokens.append(token)

                return .reading(UsageReading(session: UsageWindow(used: 7, limit: 100, resetsAt: nil),
                                             weekly: nil))
            },
            now: { now },
            log: { [unowned self] operation, details in self.logged.append((operation, details)) }
        )
    }
}

func credential(access: String = "a-1",
                expiresAt: Double?,
                refresh: String? = "r-1",
                refreshExpiresAt: Double? = nil) -> Data {
    var oauth: [String: Any] = ["accessToken": access]
    if let expiresAt { oauth["expiresAt"] = expiresAt }
    if let refresh { oauth["refreshToken"] = refresh }
    if let refreshExpiresAt { oauth["refreshTokenExpiresAt"] = refreshExpiresAt }

    return (try? JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])) ?? Data()
}

func milliseconds(_ date: Date) -> Double { date.timeIntervalSince1970 * 1000 }
