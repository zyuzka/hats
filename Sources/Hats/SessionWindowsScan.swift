import Darwin
import Foundation

struct FileStamp: Equatable {
    let seconds: Int
    let nanoseconds: Int
    let inode: UInt64
    let size: Int64

    static func find(_ path: String) -> FileStamp? {
        var facts = stat()
        guard lstat(path, &facts) == 0 else { return nil }

        return FileStamp(
            seconds: facts.st_mtimespec.tv_sec,
            nanoseconds: facts.st_mtimespec.tv_nsec,
            inode: facts.st_ino,
            size: facts.st_size
        )
    }
}

struct SessionWindowsScan {
    typealias Reader = (String, URL) -> SessionWindowRead
    typealias Log = (String, [String: String]) -> Void

    static let fileLimit = 500
    static let skippedNameLimit = 20
    static let nameShownLimit = 100

    private struct Seen {
        let stamp: FileStamp
        let read: SessionWindowRead
    }

    private var seen: [String: Seen] = [:]
    private var toldSkipped: Set<String> = []
    private var toldMarks: [String: String]?
    private let readFile: Reader
    private let log: Log

    init(read: @escaping Reader = SessionWindowFile.getRecord, log: @escaping Log = Journal.log) {
        readFile = read
        self.log = log
    }

    mutating func findWindows(in folder: URL, now: Date) -> [SessionWindow] {
        let candidates = (Self.findCandidates(in: folder) ?? []).prefix(Self.fileLimit)
        var next: [String: Seen] = [:]
        for (name, stamp) in candidates {
            if let known = seen[name], known.stamp == stamp {
                next[name] = known
                continue
            }
            let read = readFile(name, folder)
            next[name] = Seen(stamp: stamp, read: read)
            if case .skipped(let reason) = read { tellSkipped(name, reason: reason) }
        }
        seen = next
        let windows = next.values
            .compactMap { seen -> SessionWindow? in
                guard case .read(let window) = seen.read else { return nil }
                return window
            }
            .sorted { $0.session < $1.session }
        tellChanges(
            windows,
            files: candidates.count,
            now: now
        )

        return windows
    }

    static func findCandidates(in folder: URL) -> [(String, FileStamp)]? {
        var facts = stat()
        guard lstat(folder.path, &facts) == 0, facts.st_mode & S_IFMT == S_IFDIR else { return nil }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }

        return names
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
            .compactMap { name in FileStamp.find(folder.appendingPathComponent(name).path).map { (name, $0) } }
            .sorted { first, second in
                (first.1.seconds, first.1.nanoseconds, second.0) > (second.1.seconds, second.1.nanoseconds, first.0)
            }
    }

    private mutating func tellSkipped(_ name: String, reason: String) {
        guard !toldSkipped.contains(name), toldSkipped.count < Self.skippedNameLimit else { return }
        toldSkipped.insert(name)
        log("sessionWindows.skipped", [
            "name": String(name.prefix(Self.nameShownLimit)),
            "reason": reason,
        ])
    }

    private mutating func tellChanges(
        _ windows: [SessionWindow],
        files: Int,
        now: Date
    ) {
        let recent = windows.filter { $0.isRecent(at: now) }
        let marks = Dictionary(recent.map { ($0.session, $0.journalMark) }, uniquingKeysWith: { _, last in last })
        guard let told = toldMarks else {
            toldMarks = marks
            log("sessionWindows.read", [
                "files": "\(files)",
                "readable": "\(windows.count)",
                "skipped": "\(files - windows.count)",
                "recent": "\(recent.count)",
            ])
            return
        }
        for window in recent where told[window.session] != window.journalMark {
            log("sessionWindows.changed", window.journalDetails)
        }
        toldMarks = told.merging(marks) { _, new in new }
    }
}

extension SessionWindow {
    static let recentHorizon: TimeInterval = 3600

    func isRecent(at now: Date) -> Bool {
        abs(now.timeIntervalSince(measuredAt)) <= Self.recentHorizon
    }

    var journalMark: String {
        "\(state.rawValue) \(percent.map { String($0 / 10) } ?? "-")"
    }

    var journalDetails: [String: String] {
        var details = [
            "session": String(session.prefix(8)),
            "state": state.rawValue,
        ]
        if let percent { details["percent"] = "\(percent)" }
        if let tokens { details["tokens"] = "\(tokens)" }
        return details
    }
}
