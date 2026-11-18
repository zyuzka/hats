import Foundation
import NIOCore
import NIOHTTP1

extension CodexGatewayExchange {
    func noteWhatTheAnswerCarries(_ http: HTTPURLResponse, under login: CodexGatewayLogin) {
        if let turn = http.value(forHTTPHeaderField: Self.turnState), !turn.isEmpty {
            server.state.noteTurnState(turn, issuedUnder: login.hatID)
        }
        Journal.log("codexGateway.answer", [
            "path": request.path,
            "hat": String(login.hatID.prefix(8)),
            "shift": String(login.shift),
            "status": String(http.statusCode),
            "plan": http.value(forHTTPHeaderField: "x-codex-plan-type") ?? "-",
        ])
        guard let reading = CodexUsageHeaders.reading(in: { http.value(forHTTPHeaderField: $0) }) else { return }
        server.state.noteReading(reading, for: login.hatID)
        Journal.log("codexGateway.usage", CodexUsageHeaders.journalEntry(hatID: login.hatID, reading: reading))
    }

    func decide(_ http: HTTPURLResponse, _ held: Data) {
        guard let login else { return pass(http, held, isOver: true) }
        if http.statusCode == 401 { return recoverFrom401(login) }
        guard CodexHeldAnswer.isUsageLimit(status: http.statusCode, body: held), let broker = server.broker else {
            return pass(http, held, isOver: true)
        }
        tried.insert(login.hatID)
        let tried = self.tried
        phase = .deciding
        broker.usageLimit(login, tried: tried) { [weak self] next in
            self?.queue.addOperation {
                guard let self else { return }
                guard let next, !self.tried.contains(next.hatID) else {
                    Journal.log("codexGateway.limitPassedOn", ["tried": String(tried.count)])
                    return self.pass(http, held, isOver: true)
                }
                Journal.log("codexGateway.limitRetried", ["hat": String(next.hatID.prefix(8))])
                self.retry(on: next)
            }
        }
    }

    func recoverFrom401(_ login: CodexGatewayLogin) {
        guard !retriedAfter401.contains(login.hatID), let broker = server.broker else {
            server.broker?.refusedAgain(login)
            Journal.log("codexGateway.needsSignIn", ["hat": String(login.hatID.prefix(8))])
            return refuse(CodexHeldAnswer.needsSignIn)
        }
        retriedAfter401.insert(login.hatID)
        phase = .deciding
        broker.unauthorized(login) { [weak self] recovery in
            self?.queue.addOperation {
                guard let self else { return }
                switch recovery {
                case .retry(let next):
                    self.retry(on: next)
                case .needsSignIn:
                    Journal.log("codexGateway.needsSignIn", ["hat": String(login.hatID.prefix(8))])
                    self.refuse(CodexHeldAnswer.needsSignIn)
                case .unreachable:
                    Journal.log("codexGateway.renewUnreachable", ["hat": String(login.hatID.prefix(8))])
                    self.refuse(CodexHeldAnswer.renewUnreachable, status: .badGateway)
                }
            }
        }
    }

    func retry(on next: CodexGatewayLogin) {
        guard case .deciding = phase else { return }
        phase = .waiting
        send(on: next)
    }

    func holdingRanOut(attempt held: Int) {
        guard held == attempt, case .holding(let http, let data) = phase else { return }
        stopHolding(http, data, why: "timedOut")
    }

    func stopHolding(_ http: HTTPURLResponse, _ held: Data, why: String, isOver: Bool = false) {
        Journal.log("codexGateway.holdGaveUp", ["status": String(http.statusCode), "why": why])
        guard http.statusCode == 401, let login else {
            writeHead(of: http)
            writeBody(held)
            phase = .streaming
            if isOver { hangUp() }
            return
        }
        task?.cancel()
        task = nil
        recoverFrom401(login)
    }

    func pass(_ http: HTTPURLResponse, _ held: Data, isOver: Bool) {
        writeHead(of: http, length: held.count)
        writeBody(held)
        phase = .streaming
        if isOver { finish() }
    }
}
