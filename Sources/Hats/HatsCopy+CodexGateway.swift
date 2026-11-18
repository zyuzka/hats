import Foundation

extension HatsCopy {
    static let codexRestartWindowsTitle = "Codex now goes through Hats"
    static let codexRestartWindows = "Restart the Codex windows that are open, so they go through Hats. "
        + "Windows opened from now on go through it by themselves."
    static let codexAllAtLimitTitle = "All Codex hats are at their limit"
    static let codexAllAtLimit = "Every Codex hat Hats could switch to refused with usage_limit_reached, "
        + "so Codex was told about the limit."

    static func codexGatewayRunDetail(_ status: GatewayProcess.Status, hasCodexHats: Bool) -> String {
        guard hasCodexHats else { return "off — it starts once a Codex hat is added" }
        switch status {
        case .running:
            return "serving — Codex threads started from now on change hats between requests"
        case .notRunning:
            return "off — a Codex hat change reaches only Codex windows started after it"
        case .failed(let reason):
            return "could not start: \(reason)"
        }
    }

    static func codexConfigForeign(_ path: String) -> String {
        "\(path) already sets openai_base_url to another address, so Hats left it alone. "
            + "Codex threads do not go through the gateway until that line is removed."
    }

    static func codexConfigUnsupported(_ path: String) -> String {
        "\(path) has a value over several lines before its first table, which Hats does not edit. "
            + "Add openai_base_url there by hand, or move that value below a table."
    }

    static func codexConfigNotWritten(_ why: String) -> String {
        "openai_base_url could not be written to config.toml: \(why)"
    }

    static func codexThreadsLine(_ count: Int) -> String {
        switch count {
        case 0: return "no Codex thread has gone through it since it started"
        case 1: return "1 Codex thread has gone through it since it started"
        default: return "\(count) Codex threads have gone through it since it started"
        }
    }

    static func codexGatewayStopCost(threads: Int) -> String? {
        guard threads > 0 else { return nil }
        let noun = threads == 1 ? "1 Codex thread" : "\(threads) Codex threads"
        return "\(noun) went through the Codex gateway. A thread keeps the address it started with, "
            + "so it cannot reach Codex once the gateway stops. Start those threads again afterwards."
    }

    static func codexQuitCost(threads: Int) -> String? {
        guard threads > 0 else { return nil }
        let noun = threads == 1 ? "1 Codex thread" : "\(threads) Codex threads"
        return "\(noun) went through the Codex gateway, which also stops; start them again after Hats is back."
    }

    static let codexGatewayLimits = "Threads already open stay on their old address. Voice mode, the "
        + "account limits Codex shows and the model catalog of a running Codex service do not go "
        + "through the gateway."
}
