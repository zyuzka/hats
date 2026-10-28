import Foundation

struct WeekSighting: Equatable {
    let window: UsageWindow
    let isConfirmed: Bool
}

struct WeeklyMemory: Codable, Equatable {
    private(set) var hats: [String: UsageWindow] = [:]

    static var defaultURL: URL {
        StateDirectory.url.appendingPathComponent("weekly.json")
    }

    static func loaded(from url: URL = defaultURL) -> WeeklyMemory {
        guard let data = try? Data(contentsOf: url) else { return WeeklyMemory() }
        do {
            var memory = try JSONDecoder().decode(WeeklyMemory.self, from: data)
            memory.hats = memory.hats.filter { isAPlausibleWeek($0.value) }

            return memory
        } catch {
            Journal.log("weekly.unreadable", ["reason": error.localizedDescription])
            return WeeklyMemory()
        }
    }

    private static func isAPlausibleWeek(_ window: UsageWindow) -> Bool {
        (1...(Int.max / 100)).contains(window.limit) && (0...window.limit).contains(window.used)
    }

    func save(to url: URL = WeeklyMemory.defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    func remembering(_ readings: [String: UsageReading], fresh: Set<String>) -> WeeklyMemory {
        var next = self
        for id in fresh {
            guard let weekly = readings[id]?.weekly else { continue }
            next.hats[id] = weekly
        }
        return next
    }

    func kept(for liveIDs: Set<String>) -> WeeklyMemory {
        var next = self
        next.hats = hats.filter { liveIDs.contains($0.key) }
        return next
    }

    func findSighting(of id: String, readings: [String: UsageReading], fresh: Set<String>) -> WeekSighting? {
        if fresh.contains(id), let weekly = readings[id]?.weekly {
            return WeekSighting(window: weekly, isConfirmed: true)
        }
        return hats[id].map { WeekSighting(window: $0, isConfirmed: false) }
    }
}

enum WeeklySave: Equatable {
    case unchanged
    case heldBecauseTheHatsAreUnknown
    case written
    case failed(String)
}

struct WeeklyRecord {
    private(set) var memory: WeeklyMemory
    private(set) var written: WeeklyMemory
    let url: URL

    init(url: URL = WeeklyMemory.defaultURL) {
        self.url = url
        memory = WeeklyMemory.loaded(from: url)
        written = memory
    }

    static func findLiveIDs(_ ids: [String], indexIsUnusable: Bool) -> Set<String>? {
        indexIsUnusable ? nil : Set(ids)
    }

    mutating func noteAPoll(
        _ readings: [String: UsageReading],
        fresh: Set<String>,
        liveIDs: Set<String>?
    ) -> WeeklySave {
        let remembered = memory.remembering(readings, fresh: fresh)
        guard let liveIDs else {
            memory = remembered
            return .heldBecauseTheHatsAreUnknown
        }
        memory = remembered.kept(for: liveIDs)
        guard memory != written else { return .unchanged }
        do {
            try memory.save(to: url)
            written = memory
            return .written
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
