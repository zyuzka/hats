import Foundation

extension CodexGatewayRun {
    static let removalAttempts = 3

    static func isTheFirstStart(told: inout Bool) -> Bool {
        guard !told else { return false }
        told = true
        return true
    }

    @discardableResult
    func serve(port: Int, secret: String, recheck: Bool, createdByHats: inout Bool) -> GatewayProcess.Status {
        let status = start(port: port, secret: secret)
        guard status.isServing, let base = baseURL else {
            hasRemovedConfig(secret: secret, createdByHats: &createdByHats)
            return status
        }
        if recheck || configWrittenFor != base { writeConfig(base, secret: secret, createdByHats: &createdByHats) }
        return status
    }

    func retire(secret: String?, createdByHats: inout Bool) {
        for attempt in 1...Self.removalAttempts {
            if hasRemovedConfig(secret: secret, createdByHats: &createdByHats) { break }
            Journal.log("codexGateway.configRemovalRetried", ["attempt": String(attempt)])
        }
        stop()
    }

    func writeConfig(_ base: String, secret: String, createdByHats: inout Bool) {
        let file = configFile
        let existed = (try? file.read(file.target())).flatMap { $0 } != nil
        do {
            let outcome = try file.apply {
                CodexConfigText.setting(base, in: $0) { CodexGatewayPaths.isOurs($0, secret: secret) }
            }
            switch outcome {
            case .written, .unchanged:
                if outcome == .written, !existed { createdByHats = true }
                configWrittenFor = base
                configNote = nil
                Journal.log("codexGateway.config", ["outcome": outcome == .written ? "written" : "unchanged"])
            case .foreign:
                configNote = HatsCopy.codexConfigForeign(file.url.path)
                Journal.log("codexGateway.config", ["outcome": "foreign"])
            case .unsupported:
                configNote = HatsCopy.codexConfigUnsupported(file.url.path)
                Journal.log("codexGateway.config", ["outcome": "unsupported"])
            case .removed:
                configNote = nil
            }
        } catch {
            configNote = HatsCopy.codexConfigNotWritten(error.localizedDescription)
            Journal.log("codexGateway.config", ["outcome": "failed", "reason": error.localizedDescription])
        }
    }

    @discardableResult
    func hasRemovedConfig(secret: String?, createdByHats: inout Bool) -> Bool {
        defer {
            configWrittenFor = nil
            configNote = nil
        }
        guard let secret else { return true }
        do {
            let mayEmpty = createdByHats
            let isOurs: CodexIsOurs = { CodexGatewayPaths.isOurs($0, secret: secret) }
            let outcome = try configFile.apply { CodexConfigText.removing(in: $0, isOurs: isOurs, mayEmpty: mayEmpty) }
            guard outcome == .removed || outcome == .written else { return true }
            Journal.log("codexGateway.configRemoved", ["fileRemoved": String(outcome == .removed)])
            createdByHats = false
            return true
        } catch {
            Journal.log("codexGateway.configNotRemoved", ["reason": error.localizedDescription])
            return false
        }
    }
}
