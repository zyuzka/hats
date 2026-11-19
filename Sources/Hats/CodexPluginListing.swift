import Foundation

enum CodexPluginListing {
    static func findPlugins(in outcome: PluginCommandOutcome) -> Result<[CodexPluginRecord], SessionHandoffTrouble> {
        getEntries(outcome, key: "installed").flatMap { entries in
            var records: [CodexPluginRecord] = []
            for entry in entries {
                guard let id = entry["pluginId"] as? String else {
                    return .failure(.unreadable("an entry of the Codex plugin list has no pluginId"))
                }
                let source = entry["source"] as? [String: Any]
                records.append(CodexPluginRecord(
                    id: id,
                    version: entry["version"] as? String,
                    isEnabled: entry["enabled"] as? Bool ?? true,
                    path: source?["path"] as? String
                ))
            }
            return .success(records)
        }
    }

    static func findMarkets(in outcome: PluginCommandOutcome) -> Result<[CodexMarketRecord], SessionHandoffTrouble> {
        getEntries(outcome, key: "marketplaces").flatMap { entries in
            var records: [CodexMarketRecord] = []
            for entry in entries {
                guard let name = entry["name"] as? String else {
                    return .failure(.unreadable("an entry of the Codex marketplace list has no name"))
                }
                let source = entry["marketplaceSource"] as? [String: Any]
                records.append(CodexMarketRecord(
                    name: name,
                    sourceType: source?["sourceType"] as? String,
                    source: source?["source"] as? String
                ))
            }
            return .success(records)
        }
    }

    static func getEntries(
        _ outcome: PluginCommandOutcome,
        key: String
    ) -> Result<[[String: Any]], SessionHandoffTrouble> {
        if outcome.end == .timedOut { return .failure(.timedOut) }
        if let trouble = outcome.trouble { return .failure(.unreadable(trouble)) }
        guard let object = findObject(in: outcome.stdout), let array = object[key] as? [Any] else {
            return .failure(.unreadable("its answer is not one JSON object with a list under \(key)"))
        }
        let entries = array.compactMap { $0 as? [String: Any] }
        guard entries.count == array.count else { return .failure(.unreadable("its \(key) list holds a non-object")) }

        return .success(entries)
    }

    static func findObject(in stdout: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: stdout)) as? [String: Any]
    }

    static func getAnswer(
        of outcome: PluginCommandOutcome,
        findTrouble: ([String: Any]) -> String?
    ) -> PluginChangeAnswer {
        guard case .exited(let code) = outcome.end, !outcome.isTruncated else {
            return PluginChangeAnswer(isDone: false, message: outcome.trouble ?? "it did not finish")
        }
        guard code == 0 else {
            return PluginChangeAnswer(isDone: false, message: outcome.trouble ?? "exit code \(code)")
        }
        guard let object = findObject(in: outcome.stdout) else {
            return PluginChangeAnswer(isDone: false, message: "its answer held no JSON result")
        }
        if let trouble = findTrouble(object) { return PluginChangeAnswer(isDone: false, message: trouble) }

        return PluginChangeAnswer(isDone: true, message: "ok")
    }

    static func findPluginTrouble(_ object: [String: Any]) -> String? {
        guard object["pluginId"] as? String != CodexPluginProvenance.pluginID else { return nil }
        return "its answer did not name \(CodexPluginProvenance.pluginID)"
    }

    static func findMarketTrouble(_ object: [String: Any]) -> String? {
        guard object["marketplaceName"] as? String != CodexPluginProvenance.marketplaceName else { return nil }
        return "its answer did not name the marketplace \(CodexPluginProvenance.marketplaceName)"
    }

    static func findUpgradeTrouble(_ object: [String: Any]) -> String? {
        guard let errors = object["errors"] as? [Any] else { return "its answer had no errors list" }
        guard !errors.isEmpty else { return nil }
        let said = errors.map { error -> String in
            if let text = error as? String { return text }
            guard JSONSerialization.isValidJSONObject(error) else { return "\(error)" }
            let data = try? JSONSerialization.data(withJSONObject: error, options: [.sortedKeys])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\(error)"
        }

        return "it reported: " + said.joined(separator: "; ")
    }
}
