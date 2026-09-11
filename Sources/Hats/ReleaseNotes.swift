import Foundation

struct ReleaseNote: Equatable, Identifiable {
    let version: String
    let dateline: String
    let lines: [String]

    var id: String { version }
}

enum ReleaseNotes {
    static let resource = "CHANGELOG"
    static let versionHeading = "## "

    static func parse(_ markdown: String) -> [ReleaseNote] {
        var notes: [ReleaseNote] = []
        var version: String?
        var dateline = ""
        var lines: [String] = []

        func close() {
            guard let version else { return }
            notes.append(ReleaseNote(version: version, dateline: dateline, lines: trimmed(lines)))
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            guard let heading = heading(of: line) else {
                if version != nil { lines.append(line) }
                continue
            }
            close()
            version = heading.version
            dateline = heading.dateline
            lines = []
        }
        close()
        return notes
    }

    static func heading(of line: String) -> (version: String, dateline: String)? {
        guard line.hasPrefix(versionHeading) else { return nil }
        let rest = line.dropFirst(versionHeading.count).trimmingCharacters(in: .whitespaces)
        guard let first = rest.split(separator: " ").first.map(String.init),
              isAVersion(first) else { return nil }
        let dateline = rest.dropFirst(first.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: " —-–"))
        return (first, dateline)
    }

    static func isAVersion(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    private static func trimmed(_ lines: [String]) -> [String] {
        var lines = lines
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines
    }

    static func fromTheBundle(_ bundle: Bundle = .main) -> [ReleaseNote] {
        guard let url = bundle.url(forResource: resource, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }
}
