import Foundation

enum CodexConfigEdit: Equatable {
    case unchanged
    case changed(String)
    case emptied
    case foreign(String)
    case unsupported
}

typealias CodexIsOurs = (String) -> Bool

enum CodexConfigText {
    static let key = "openai_base_url"

    struct Found: Equatable {
        let line: Int
        let value: String?
    }

    static func find(in text: String) -> Found? {
        let lines = text.components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") { return nil }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard [key, "\"\(key)\"", "'\(key)'"].contains(name) else { continue }
            return Found(line: index, value: quoted(String(line[line.index(after: equals)...])))
        }

        return nil
    }

    static func quoted(_ rest: String) -> String? {
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard let quote = text.first, quote == "\"" || quote == "'" else { return nil }
        let body = text.dropFirst()
        guard let close = body.firstIndex(of: quote) else { return nil }
        let tail = body[body.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard tail.isEmpty || tail.hasPrefix("#") else { return nil }

        return String(body[..<close])
    }

    static func line(for value: String) -> String { "\(key) = \"\(value)\"" }

    static func isCRLF(_ text: String) -> Bool { text.contains("\r\n") }

    static func hasAMultiLineValueOnTop(_ text: String) -> Bool {
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") { return false }
            if line.contains("\"\"\"") || line.contains("'''") { return true }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equals)...]
            let opens = value.filter { $0 == "[" || $0 == "{" }.count
            let closes = value.filter { $0 == "]" || $0 == "}" }.count
            if opens > closes { return true }
        }
        return false
    }

    static func setting(_ value: String, in text: String?, isOurs: CodexIsOurs) -> CodexConfigEdit {
        guard let text else { return .changed(line(for: value) + "\n") }
        guard !hasAMultiLineValueOnTop(text) else { return .unsupported }
        let carriage = isCRLF(text) ? "\r" : ""
        var lines = text.components(separatedBy: "\n")
        if let found = find(in: text) {
            guard let current = found.value, isOurs(current) else { return .foreign(found.value ?? "unreadable") }
            guard current != value else { return .unchanged }
            lines[found.line] = line(for: value) + (lines[found.line].hasSuffix("\r") ? "\r" : "")
            return .changed(lines.joined(separator: "\n"))
        }
        let firstTable = lines.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") }
        guard let firstTable else {
            let ended = text.isEmpty || text.hasSuffix("\n") || text.hasSuffix("\r\n")
            let joined = ended ? text : text + carriage + "\n"
            return .changed(joined + line(for: value) + carriage + "\n")
        }
        lines.insert(line(for: value) + carriage, at: firstTable)

        return .changed(lines.joined(separator: "\n"))
    }

    static func removing(in text: String?, isOurs: CodexIsOurs, mayEmpty: Bool) -> CodexConfigEdit {
        guard let text else { return .unchanged }
        guard !hasAMultiLineValueOnTop(text) else { return .unsupported }
        guard let found = find(in: text) else { return .unchanged }
        guard let current = found.value, isOurs(current) else { return .foreign(found.value ?? "unreadable") }
        var lines = text.components(separatedBy: "\n")
        lines.remove(at: found.line)
        let left = lines.joined(separator: "\n")
        if mayEmpty, left.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptied }

        return .changed(left)
    }
}
