import Foundation

enum SessionHandoffOldHook {
    static func findRefusal(configFolder: String, in world: PluginWorld) -> SessionHandoffRefusal? {
        let file = URL(fileURLWithPath: configFolder).appendingPathComponent("settings.json").path
        switch world.readFile(file) {
        case .missing:
            return nil
        case .unreadable(let reason):
            return .brokenSettings(file: file, reason: reason)
        case .read(let data):
            guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return .brokenSettings(file: file, reason: "it is not a JSON object")
            }
            let commands = findHandoffStarts(in: root)
            return commands.isEmpty ? nil : .oldHook(file: file, commands: commands)
        }
    }

    static func findHandoffStarts(in root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any],
              let groups = hooks["SessionStart"] as? [Any] else { return [] }

        return groups
            .compactMap { ($0 as? [String: Any])?["hooks"] as? [Any] }
            .flatMap { $0 }
            .compactMap { ($0 as? [String: Any])?["command"] as? String }
            .filter(isHandoffStart)
    }

    static func isHandoffStart(_ command: String) -> Bool {
        guard !command.contains("CLAUDE_PLUGIN_ROOT") else { return false }
        let words = command
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        guard let script = words.firstIndex(where: { $0.split(separator: "/").last == "handoff.py" }) else {
            return false
        }

        return words[words.index(after: script)...].contains("start")
    }
}
