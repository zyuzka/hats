import Foundation

enum ShellDialect: Equatable {
    case posix
    case fish
    case csh

    func exportLine(_ name: String, _ value: String) -> String {
        switch self {
        case .posix:
            return "export \(name)=\(value)"
        case .fish:
            return "set -gx \(name) \(value)"
        case .csh:
            return "setenv \(name) \(value)"
        }
    }

    func guarded(_ lines: [String], byTheAnswerTo probe: String, containing marker: String) -> [String] {
        let body = lines.map { "    " + $0 }
        let matcher = "\(ShellEnvironment.grepPath) -qF -- \(marker)"
        switch self {
        case .posix:
            return ["if \(probe) | \(matcher); then"] + body + ["fi"]
        case .fish:
            return ["if \(probe) | \(matcher)"] + body + ["end"]
        case .csh:
            return ["if ( \"`\(probe)`\" =~ *\(marker)* ) then"] + body + ["endif"]
        }
    }

    func value(in line: String, name: String) -> String? {
        let words = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        switch self {
        case .posix:
            let assignments = words.first == "export" ? Array(words.dropFirst()) : words
            guard let ours = Self.assignment(named: name, among: assignments) else { return nil }
            return Self.firstWord(of: ours)
        case .fish:
            guard words.count >= 4, words[0] == "set", ["-gx", "-x"].contains(words[1]),
                  words[2] == name, !Self.isComment(words[3]) else { return nil }
            return Self.firstWord(of: words[3])
        case .csh:
            guard words.count >= 3, words[0] == "setenv", words[1] == name,
                  !Self.isComment(words[2]) else { return nil }
            return Self.firstWord(of: words[2])
        }
    }

    func containsAnAssignment(to name: String, in line: String) -> Bool {
        let words = Self.beforeAnyComment(of: line)
        switch self {
        case .posix:
            return words.contains { word in
                guard let equals = word.firstIndex(of: "=") else { return false }
                return word[..<equals] == name
            }
        case .fish:
            return Self.hasAnAssignment(in: words, keyword: "set", flags: ["-gx", "-x"], to: name)
        case .csh:
            return Self.hasAnAssignment(in: words, keyword: "setenv", flags: nil, to: name)
        }
    }

    private static func hasAnAssignment(
        in words: [String],
        keyword: String,
        flags: Set<String>?,
        to name: String
    ) -> Bool {
        for (index, word) in words.enumerated() where word == keyword {
            guard let flags else {
                if index + 1 < words.count, words[index + 1] == name { return true }
                continue
            }
            guard index + 2 < words.count, flags.contains(words[index + 1]) else { continue }
            if words[index + 2] == name { return true }
        }
        return false
    }

    func isOnlyAnAssignment(to name: String, in line: String) -> Bool {
        let words = Self.beforeAnyComment(of: line)
        switch self {
        case .posix:
            let assignments = words.first == "export" ? Array(words.dropFirst()) : words
            guard assignments.count == 1, let word = assignments.first,
                  let equals = word.firstIndex(of: "=") else { return false }
            return word[..<equals] == name && Self.isAPlainValue(String(word[word.index(after: equals)...]))
        case .fish:
            return words.count == 4 && words[0] == "set" && ["-gx", "-x"].contains(words[1])
                && words[2] == name && Self.isAPlainValue(words[3])
        case .csh:
            return words.count == 3 && words[0] == "setenv" && words[1] == name && Self.isAPlainValue(words[2])
        }
    }

    static func isAPlainValue(_ raw: String) -> Bool {
        var quote: Character?
        for character in raw {
            if character == "`", quote != "'" { return false }
            if let open = quote {
                if character == open { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if terminators.contains(character) { return false }
        }
        return quote == nil
    }

    private static func beforeAnyComment(of line: String) -> [String] {
        var out: [String] = []
        for word in line.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
            if isComment(word) { break }
            out.append(word)
        }
        return out
    }

    private static func isComment(_ token: String) -> Bool {
        token.hasPrefix("#")
    }

    private static func assignment(named name: String, among words: [String]) -> String? {
        for word in words {
            if isComment(word) { return nil }
            guard let equals = word.firstIndex(of: "=") else { return nil }
            if word[..<equals] == name { return String(word[word.index(after: equals)...]) }
        }
        return nil
    }

    private static let terminators: Set<Character> = [";", "&", "|", "<", ">", "(", ")"]

    private static func firstWord(of raw: String) -> String? {
        if let quote = raw.first, quote == "\"" || quote == "'" {
            let quoted = raw.dropFirst().prefix { $0 != quote }
            return quoted.isEmpty ? nil : String(quoted)
        }
        let word = raw.prefix {
            !$0.isWhitespace && !terminators.contains($0) && $0 != "\"" && $0 != "'"
        }
        return word.isEmpty ? nil : String(word)
    }
}
