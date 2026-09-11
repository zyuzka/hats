import Foundation

extension HatsCopy {
    static func retiredListener(port: Int, dependants: Int?, keptByTheTypedPort: Bool) -> String {
        let who: String
        switch dependants {
        case nil: who = "sessions that could not be counted"
        case 0: who = "no live session"
        case 1: who = "1 live session"
        case let some?: who = "\(some) live sessions"
        }
        return keptByTheTypedPort
            ? "port \(port) is still listening for \(who) — applying it moves back to that listener"
            : "port \(port) is still listening for \(who) — applying a different port closes it"
    }

    static func followsASwitch(settleSeconds: Int) -> String {
        guard settleSeconds > 0 else { return "at its next request after a switch" }
        return "at its first request \(settleSeconds) s after a switch, about \(settleSeconds + 10) s in practice"
    }

    static func gatewayRunDetail(_ status: GatewayProcess.Status, settleSeconds: Int) -> String {
        switch status {
        case .running:
            return "serving — a session started through it moves "
                + followsASwitch(settleSeconds: settleSeconds)
        case .notRunning: return "off — hats change at the next renewal"
        case .failed(let reason): return "could not start: \(reason)"
        }
    }

    static func whenSessionsChangeHats(settleSeconds: Int) -> String {
        "Sessions started through the gateway change "
            + followsASwitch(settleSeconds: settleSeconds)
            + "; every other session at its next token renewal."
    }

    static func settleWarning(settleSeconds: Int) -> String? {
        guard AppSettings.isAUsableSettle(settleSeconds) else { return nil }
        guard AppSettings.isBelowTheDefaultSettle(settleSeconds) else { return nil }
        return "below \(Int(GatewayRefusal.defaultSettle)) s a session is refused while its own "
            + "credential cache may still hold the token that just failed — measured at 2 s it "
            + "re-read the keychain and moved on the next request, one refusal per session, but "
            + "that is one measurement rather than a guarantee"
    }

    static func gatewayStopCost(ports: [Int], sessions: [Session]?) -> String? {
        cost(
            ports: ports,
            sessions: sessions,
            ending: "Turning the gateway off closes the port they are pointed at, and nothing takes "
                + "its place. A session cannot reach Claude until the gateway is back on the same "
                + "port, or until you unset the gateway variables in that session's shell and start "
                + "the session again."
        )
    }

    static func gatewayRestartCost(ports: [Int], sessions: [Session]?) -> String? {
        cost(
            ports: ports,
            sessions: sessions,
            ending: "Restarting closes the listener and opens it again on the same port. A request "
                + "that lands in between fails, and if the port cannot be taken back the gateway "
                + "stays down until it can."
        )
    }

    private static func cost(ports: [Int], sessions: [Session]?, ending: String) -> String? {
        guard let sessions else {
            return "The process table could not be read, so Hats cannot say what is running through "
                + "the gateway. \(ending)"
        }
        let dependants = GatewayRetirement.dependants(onAnyOf: ports, among: sessions)
        guard !dependants.isEmpty else { return nil }
        let noun = "\(dependants.count) live session\(dependants.count == 1 ? "" : "s")"
        let pids = dependants.map(\.pid).sorted().map(String.init).joined(separator: ", ")
        return "\(noun) running through the gateway (pid \(pids)). \(ending)"
    }

    static func gateway(_ status: GatewayProcess.Status) -> String {
        switch status {
        case .running: return "Gateway on \(GatewayProcess.port)"
        case .notRunning: return "Gateway is off — hats change at the next renewal"
        case .failed(let reason): return "Gateway could not start: \(reason)"
        }
    }
}
