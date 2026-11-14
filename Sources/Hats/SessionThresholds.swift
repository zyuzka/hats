import Darwin
import Foundation

final class SessionThresholds {
    static let pollSpell: TimeInterval = 5

    private let folder: URL
    private let retryAfter: TimeInterval
    private let pollEvery: TimeInterval
    private let queue = DispatchQueue(label: "hats.session-thresholds", qos: .utility)
    private let log: SessionThresholdsScan.Log
    private var scan: SessionThresholdsScan
    private var source: DispatchSourceFileSystemObject?
    private var isScheduled = false
    private var lastScan = Date.distantPast
    private var lastTrouble = NoteOnChange()
    private var isStopped = false

    var onRead: ((SessionStagesRead) -> Void)?

    init(
        folder: URL,
        retryAfter: TimeInterval = SessionWindows.retrySpell,
        pollEvery: TimeInterval = SessionThresholds.pollSpell,
        list: @escaping SessionThresholdsScan.Lister = SessionWindowsScan.findCandidates,
        log: @escaping SessionThresholdsScan.Log = Journal.log
    ) {
        self.folder = folder
        self.retryAfter = retryAfter
        self.pollEvery = pollEvery
        scan = SessionThresholdsScan(list: list, log: log)
        self.log = log
    }

    func start() {
        queue.async { [self] in
            watchAndScan()
            schedulePoll()
        }
    }

    func stop() {
        onRead = nil
        queue.async { [self] in
            isStopped = true
            source?.cancel()
            source = nil
        }
    }

    private func watchAndScan() {
        guard source == nil, !isStopped else { return }
        if let trouble = SessionWindows.findTroubleMakingTheFolder(folder) {
            giveUpForNow(trouble)
            return
        }
        let descriptor = open(folder.path, O_EVTONLY | O_NOFOLLOW | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else {
            giveUpForNow(String(cString: strerror(errno)))
            return
        }
        lastTrouble.clear()
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [
                .write,
                .delete,
                .rename,
            ],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.noteAChange() }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
        scanNow()
    }

    private func giveUpForNow(_ trouble: String) {
        queue.asyncAfter(deadline: .now() + retryAfter) { [weak self] in self?.watchAndScan() }
        guard lastTrouble.shouldWrite(trouble) else { return }
        log("sessionThresholds.unwatched", [
            "reason": trouble,
        ])
    }

    private func noteAChange() {
        guard let source else { return }
        guard source.data.isDisjoint(with: SessionWindows.lossOfTheFolder) else {
            source.cancel()
            self.source = nil
            queue.asyncAfter(deadline: .now() + SessionWindows.quietSpell) { [weak self] in self?.watchAndScan() }
            return
        }
        scheduleAScan()
    }

    private func scheduleAScan() {
        guard !isScheduled else { return }
        isScheduled = true
        let wait = max(0, SessionWindows.quietSpell - Date().timeIntervalSince(lastScan))
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, !isStopped else { return }
            isScheduled = false
            scanNow()
        }
    }

    private func schedulePoll() {
        queue.asyncAfter(deadline: .now() + pollEvery) { [weak self] in
            guard let self, !isStopped else { return }
            if source != nil { scanNow() }
            schedulePoll()
        }
    }

    private func scanNow() {
        lastScan = Date()
        guard let found = scan.findStages(in: folder, now: lastScan) else { return }
        DispatchQueue.main.async { [weak self] in self?.onRead?(found) }
    }
}
