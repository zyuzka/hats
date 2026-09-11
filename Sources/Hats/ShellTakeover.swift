import Foundation

extension ShellEnvironment {
    static func takenOver(profile: String, baseURL: String, dialect: ShellDialect) -> String? {
        guard case .foreign = verdict(profile: profile, baseURL: baseURL, dialect: dialect, serving: true)
        else { return nil }

        var kept: [Substring] = []
        var previous: String?
        for line in profile.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            guard dialect.containsAnAssignment(to: baseURLName, in: text) else {
                kept.append(line)
                if !text.allSatisfy(\.isWhitespace) { previous = text }
                continue
            }
            guard dialect.isOnlyAnAssignment(to: baseURLName, in: text),
                  !isNested(text, after: previous) else { return nil }
        }

        let remaining = kept.joined(separator: "\n")
        return applied(to: remaining, baseURL: baseURL, dialect: dialect, serving: true)
    }

    static func isNested(_ line: String, after previous: String?) -> Bool {
        if line.first?.isWhitespace == true { return true }
        guard let previous else { return false }
        let words = previous.split(whereSeparator: \.isWhitespace).map(String.init).prefix { !$0.hasPrefix("#") }
        guard let first = words.first, let last = words.last else { return false }
        let openers: Set<String> = ["then", "do", "else", "{", "(", "begin"]
        let heads: Set<String> = ["if", "function", "while", "for", "foreach", "switch", "case", "else"]
        return openers.contains(last) || heads.contains(first)
    }
}
