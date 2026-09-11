import Foundation

enum GatewayProcess {
    static var port = 8787

    static var baseURL: String { baseURL(port: port) }

    static func baseURL(port: Int) -> String { "http://127.0.0.1:\(port)" }

    private struct Listeners {
        var serving: GatewayServer?
        var retired: GatewayServer?
    }

    private static var listeners = Listeners() {
        didSet { GatewayHeldPorts.shared.replace(with: heldPorts) }
    }

    private static var server: GatewayServer? {
        get { listeners.serving }
        set { listeners.serving = newValue }
    }

    private static var retired: GatewayServer? {
        get { listeners.retired }
        set { listeners.retired = newValue }
    }
    private static var lastOutcome: Status?

    private(set) static var lastPortRefusal: String?

    static var servingPort: Int? { listeningPort(of: server) }

    static var retiredPort: Int? { listeningPort(of: retired) }

    static var hasARetiredListener: Bool { retired != nil }

    static var heldPorts: [Int] { [servingPort, retiredPort].compactMap { $0 } }

    private static func listeningPort(of listener: GatewayServer?) -> Int? {
        guard let listener, listener.isServing else { return nil }
        return listener.boundPort ?? listener.port
    }

    @discardableResult
    static func restart(on newPort: Int, settle: TimeInterval = GatewayRefusal.defaultSettle) -> Status {
        stop()
        port = newPort
        return start(settle: settle)
    }

    @discardableResult
    static func moveTo(port newPort: Int, settle: TimeInterval = GatewayRefusal.defaultSettle) -> Status {
        if let server, !server.isServing { stopTheCurrentListener() }
        switch GatewayPortChange.plan(servingPort: servingPort, retiredPort: retiredPort, requested: newPort) {
        case .unchanged:
            lastPortRefusal = nil
            return status
        case .promoteRetired:
            listeners = Listeners(serving: listeners.retired, retired: listeners.serving)
            port = newPort
            applySettle(settle)
            lastOutcome = .running
            lastPortRefusal = nil
            Journal.log("gateway.portPromoted", ["port": String(newPort)])
            return .running
        case .bind:
            return bound(alongsideOn: newPort, settle: settle)
        }
    }

    private static func attempted(on candidatePort: Int, settle: TimeInterval) -> (GatewayServer, Status) {
        let candidate = GatewayServer(
            port: candidatePort,
            refusal: GatewayRefusal(settle: settle, account: GatewayServer.liveAccountAddress())
        )
        var started = true
        do {
            try candidate.start()
        } catch {
            started = false
            Journal.log("gateway.failed", ["reason": error.localizedDescription])
        }
        return (candidate, outcome(started: started, serving: candidate.isServing))
    }

    private static func bound(alongsideOn newPort: Int, settle: TimeInterval) -> Status {
        let (candidate, attempt) = attempted(on: newPort, settle: settle)
        guard attempt.isServing else {
            candidate.stop()
            lastPortRefusal = refusalReason(of: attempt)
            if server == nil { lastOutcome = attempt }
            Journal.log("gateway.portRefused", ["port": String(newPort), "keptOn": String(port)])
            return attempt
        }

        closeTheRetiredListener()
        listeners = Listeners(serving: candidate, retired: server)
        port = newPort
        lastOutcome = attempt
        lastPortRefusal = nil
        Journal.log("gateway.started", [
            "port": String(newPort),
            "retired": retiredPort.map(String.init) ?? "-",
        ])
        return attempt
    }

    @discardableResult
    static func start(settle: TimeInterval = GatewayRefusal.defaultSettle) -> Status {
        if let server, server.isServing { return .running }
        lastPortRefusal = nil
        stopTheCurrentListener()

        let (candidate, status) = attempted(on: port, settle: settle)
        lastOutcome = status
        if status.isServing {
            server = candidate
            Journal.log("gateway.started", ["port": String(port)])
        } else {
            candidate.stop()
        }
        return status
    }

    static func stop() {
        lastPortRefusal = nil
        closeTheRetiredListener()
        stopTheCurrentListener()
    }

    static func closeTheRetiredListener() {
        guard let retired else { return }
        retired.stop()
        Journal.log("gateway.retiredClosed", ["port": String(retired.boundPort ?? retired.port)])
        self.retired = nil
    }

    private static func stopTheCurrentListener() {
        guard let server else { return }
        let held = server.boundPort ?? server.port
        server.stop()
        Journal.log("gateway.stopped", ["port": String(held)])
        self.server = nil
        lastOutcome = nil
    }

    static var sessionRows: [GatewaySessionRow] {
        GatewaySessions.merged([server, retired].compactMap { $0?.ledger.sessionRows })
    }

    static var status: Status {
        reported(serving: server?.isServing ?? false, last: lastOutcome)
    }

    static var refusalsSoFar: Int { server?.refusal?.refusals ?? 0 }

    static var settleInForce: TimeInterval? { server?.refusal?.settleSeconds }

    static var retiredSettleInForce: TimeInterval? { retired?.refusal?.settleSeconds }

    static func applySettle(_ seconds: TimeInterval) {
        server?.refusal?.useSettle(seconds)
        retired?.refusal?.useSettle(seconds)
        Journal.log("gateway.settle", ["seconds": String(Int(seconds))])
    }
}
