import Darwin
import Foundation

struct SessionStagesRead: Equatable {
    let stages: [SessionStage]
    let listed: Set<String>
}

struct SessionThresholdsScan {
    typealias Reader = (String, URL) -> SessionStageRead
    typealias Lister = (URL) -> [(String, FileStamp)]?
    typealias Log = (String, [String: String]) -> Void

    static let keptFor: TimeInterval = 30 * 86400
    static let sweepLimit = 200

    private struct Seen {
        let stamp: FileStamp
        let read: SessionStageRead
    }

    private var seen: [String: Seen] = [:]
    private var toldSkipped: Set<String> = []
    private var toldLimitTrouble: Set<String> = []
    private var toldSweepFailure = NoteOnChange()
    private var toldUnlisted = NoteOnChange()
    private let list: Lister
    private let readFile: Reader
    private let log: Log

    init(
        list: @escaping Lister = SessionWindowsScan.findCandidates,
        read: @escaping Reader = SessionStageFile.getRecord,
        log: @escaping Log = Journal.log
    ) {
        self.list = list
        readFile = read
        self.log = log
    }

    mutating func findStages(in folder: URL, now: Date) -> SessionStagesRead? {
        guard let listing = list(folder) else {
            if toldUnlisted.shouldWrite("unlisted") { log("sessionThresholds.unlisted", [:]) }
            return nil
        }
        toldUnlisted.clear()
        var next: [String: Seen] = [:]
        for (name, stamp) in listing.prefix(SessionWindowsScan.fileLimit) {
            if let known = seen[name], known.stamp == stamp {
                next[name] = known
                continue
            }
            let read = readFile(name, folder)
            next[name] = Seen(stamp: stamp, read: read)
            if case .skipped(let reason) = read { tellSkipped(name, reason: reason) }
            if case .read(let stage) = read, let trouble = stage.limitTrouble {
                tellLimitTrouble(name, trouble: trouble)
            }
        }
        var listed = Set(listing.map(\.0))
        sweepExpired(findExpired(listing, reads: next, now: now), in: folder, from: &listed)
        seen = next.filter { listed.contains($0.key) }
        let stages = seen.values
            .compactMap { seen -> SessionStage? in
                guard case .read(let stage) = seen.read else { return nil }
                return stage
            }
            .sorted { $0.session < $1.session }

        return SessionStagesRead(stages: stages, listed: Set(listed.map { String($0.dropLast(".json".count)) }))
    }

    private func findExpired(_ listing: [(String, FileStamp)], reads: [String: Seen], now: Date) -> [String] {
        let oldest = now.addingTimeInterval(-Self.keptFor)
        let expired = listing.compactMap { name, stamp -> String? in
            guard case .read(let stage)? = reads[name]?.read else {
                return Date(timeIntervalSince1970: TimeInterval(stamp.seconds)) < oldest ? name : nil
            }
            return stage.at < oldest ? name : nil
        }

        return Array(expired.sorted().prefix(Self.sweepLimit))
    }

    private mutating func sweepExpired(_ names: [String], in folder: URL, from listed: inout Set<String>) {
        var hasFailed = false
        for name in names {
            guard unlink(folder.appendingPathComponent(name).path) != 0, errno != ENOENT else {
                listed.remove(name)
                continue
            }
            hasFailed = true
            let reason = String(cString: strerror(errno))
            guard toldSweepFailure.shouldWrite(reason) else { continue }
            log("sessionThresholds.notSwept", [
                "name": String(name.prefix(SessionWindowsScan.nameShownLimit)),
                "reason": reason,
            ])
        }
        if !hasFailed { toldSweepFailure.clear() }
    }

    private mutating func tellLimitTrouble(_ name: String, trouble: String) {
        let isFull = toldLimitTrouble.count >= SessionWindowsScan.skippedNameLimit
        guard !toldLimitTrouble.contains(name), !isFull else { return }
        toldLimitTrouble.insert(name)
        log("sessionThresholds.limitsSkipped", [
            "name": String(name.prefix(SessionWindowsScan.nameShownLimit)),
            "reason": trouble,
        ])
    }

    private mutating func tellSkipped(_ name: String, reason: String) {
        guard !toldSkipped.contains(name), toldSkipped.count < SessionWindowsScan.skippedNameLimit else { return }
        toldSkipped.insert(name)
        log("sessionThresholds.skipped", [
            "name": String(name.prefix(SessionWindowsScan.nameShownLimit)),
            "reason": reason,
        ])
    }
}
