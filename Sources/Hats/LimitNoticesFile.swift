import Foundation

struct LimitNoticeEntry: Codable, Equatable {
    let hat: String
    let limit: StageLimit
    let stage: LimitStage
    let resetsAt: Date
    let toldAt: Date

    enum CodingKeys: String, CodingKey {
        case hat
        case limit
        case stage
        case resetsAt = "resets_at"
        case toldAt = "told_at"
    }
}

struct LimitNoticesFile {
    typealias Log = (String, [String: String]) -> Void

    static let name = "limit-notices.json"

    private struct Fields: Codable {
        let entries: [LimitNoticeEntry]
    }

    let url: URL
    private let log: Log
    private var lastSaveFailure = NoteOnChange()

    init(root: URL, log: @escaping Log) {
        url = root.appendingPathComponent(Self.name)
        self.log = log
    }

    func getEntries() -> [LimitNoticeEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let fields = try? decoder.decode(Fields.self, from: data) else {
            log("limitNotices.unreadable", [:])
            return []
        }

        return fields.entries
    }

    mutating func setEntries(_ entries: [LimitNoticeEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
        ]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(Fields(entries: entries)).write(to: url, options: .atomic)
            lastSaveFailure.clear()
        } catch {
            guard lastSaveFailure.shouldWrite(error.localizedDescription) else { return }
            log("limitNotices.notSaved", [
                "reason": error.localizedDescription,
            ])
        }
    }
}
