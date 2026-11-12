import Foundation

struct PluginRecord: Equatable {
    let id: String
    let scope: String
    let version: String?
    let projectPath: String?
    let isEnabled: Bool
}

struct MarketplaceRecord: Equatable {
    let name: String
    let source: String
    let repo: String?
    let path: String?
}

struct PluginChangeAnswer: Equatable {
    let isDone: Bool
    let message: String
}

enum SessionHandoffListing {
    static func findPlugins(in outcome: PluginCommandOutcome) -> Result<[PluginRecord], SessionHandoffTrouble> {
        getArray(outcome).flatMap { entries in
            var records: [PluginRecord] = []
            for entry in entries {
                guard let id = entry["id"] as? String, let scope = entry["scope"] as? String else {
                    return .failure(.unreadable("an entry of the plugin list has no id or scope"))
                }
                records.append(PluginRecord(
                    id: id,
                    scope: scope,
                    version: entry["version"] as? String,
                    projectPath: entry["projectPath"] as? String,
                    isEnabled: entry["enabled"] as? Bool ?? true
                ))
            }
            return .success(records)
        }
    }

    static func findMarketplaces(
        in outcome: PluginCommandOutcome
    ) -> Result<[MarketplaceRecord], SessionHandoffTrouble> {
        getArray(outcome).flatMap { entries in
            var records: [MarketplaceRecord] = []
            for entry in entries {
                guard let name = entry["name"] as? String, let source = entry["source"] as? String else {
                    return .failure(.unreadable("an entry of the marketplace list has no name or source"))
                }
                records.append(MarketplaceRecord(
                    name: name,
                    source: source,
                    repo: entry["repo"] as? String,
                    path: entry["path"] as? String
                ))
            }
            return .success(records)
        }
    }

    static func getArray(_ outcome: PluginCommandOutcome) -> Result<[[String: Any]], SessionHandoffTrouble> {
        if outcome.end == .timedOut { return .failure(.timedOut) }
        if let trouble = outcome.trouble { return .failure(.unreadable(trouble)) }
        guard let parsed = try? JSONSerialization.jsonObject(with: outcome.stdout),
              let array = parsed as? [Any] else {
            return .failure(.unreadable("its answer is not one JSON list"))
        }
        let entries = array.compactMap { $0 as? [String: Any] }
        guard entries.count == array.count else { return .failure(.unreadable("its list holds a non-object")) }

        return .success(entries)
    }

    static func getAnswer(of outcome: PluginCommandOutcome) -> PluginChangeAnswer {
        let object = findLastObject(in: outcome.stdout)
        let message = object?["message"] as? String
        guard case .exited(let code) = outcome.end, !outcome.isTruncated else {
            return PluginChangeAnswer(isDone: false, message: outcome.trouble ?? "it did not finish")
        }
        guard let object else {
            return PluginChangeAnswer(isDone: false, message: outcome.trouble ?? "its answer held no JSON result")
        }
        let isDone = code == 0 && object["outcome"] as? String == "ok"

        return PluginChangeAnswer(isDone: isDone, message: message ?? outcome.trouble ?? "exit code \(code)")
    }

    static func getUpdateAnswer(of outcome: PluginCommandOutcome) -> PluginChangeAnswer {
        let answer = getAnswer(of: outcome)
        let isRefreshFailed = findLastObject(in: outcome.stdout)?["refreshFailed"] as? Bool == true
        guard answer.isDone, isRefreshFailed else { return answer }

        return PluginChangeAnswer(isDone: false, message: answer.message)
    }

    static func findLastObject(in stdout: Data) -> [String: Any]? {
        let lines = (String(bytes: stdout, encoding: .utf8) ?? "").split(separator: "\n").reversed()
        for line in lines {
            let data = Data(line.utf8)
            if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { return object }
        }

        return nil
    }
}

enum SessionHandoffTrouble: Error, Equatable {
    case timedOut
    case unreadable(String)

    var text: String {
        switch self {
        case .timedOut: return "timed out"
        case .unreadable(let reason): return reason
        }
    }
}
