import Darwin
import Foundation

final class SessionWindows {
    static let quietSpell: TimeInterval = 1
    static let retrySpell: TimeInterval = 60
    static let lossOfTheFolder: DispatchSource.FileSystemEvent = [
        .delete,
        .rename,
    ]

    private let folder: URL
    private let retryAfter: TimeInterval
    private let queue = DispatchQueue(label: "hats.session-windows", qos: .utility)
    private let log: SessionWindowsScan.Log
    private var scan: SessionWindowsScan
    private var source: DispatchSourceFileSystemObject?
    private var isScheduled = false
    private var lastScan = Date.distantPast
    private var lastTrouble = NoteOnChange()
    private var isStopped = false

    private(set) var windows: [SessionWindow] = []
    var onChange: (() -> Void)?

    init(
        folder: URL,
        retryAfter: TimeInterval = SessionWindows.retrySpell,
        log: @escaping SessionWindowsScan.Log = Journal.log
    ) {
        self.folder = folder
        self.retryAfter = retryAfter
        scan = SessionWindowsScan(log: log)
        self.log = log
    }

    static var defaultFolder: URL {
        StateDirectory.url.appendingPathComponent(SessionWindow.folderName)
    }

    func start() {
        queue.async { [self] in watchAndScan() }
    }

    func stop() {
        queue.async { [self] in
            isStopped = true
            source?.cancel()
            source = nil
        }
    }

    private func watchAndScan() {
        guard source == nil, !isStopped else { return }
        if let trouble = Self.findTroubleMakingTheFolder(folder) {
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
        DispatchQueue.main.async { [weak self] in self?.show([]) }
        queue.asyncAfter(deadline: .now() + retryAfter) { [weak self] in self?.watchAndScan() }
        guard lastTrouble.shouldWrite(trouble) else { return }
        log("sessionWindows.unwatched", [
            "reason": trouble,
        ])
    }

    private func noteAChange() {
        guard let source else { return }
        guard source.data.isDisjoint(with: Self.lossOfTheFolder) else {
            source.cancel()
            self.source = nil
            queue.asyncAfter(deadline: .now() + Self.quietSpell) { [weak self] in self?.watchAndScan() }
            return
        }
        scheduleAScan()
    }

    private func scheduleAScan() {
        guard !isScheduled else { return }
        isScheduled = true
        let wait = max(0, Self.quietSpell - Date().timeIntervalSince(lastScan))
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.isScheduled = false
            self?.scanNow()
        }
    }

    private func scanNow() {
        lastScan = Date()
        let found = scan.findWindows(in: folder, now: lastScan)
        DispatchQueue.main.async { [weak self] in self?.show(found) }
    }

    private func show(_ found: [SessionWindow]) {
        guard found != windows else { return }
        windows = found
        onChange?()
    }

    static func findTroubleMakingTheFolder(_ folder: URL) -> String? {
        do {
            try FileManager.default.createDirectory(
                at: folder.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return error.localizedDescription
        }
        if mkdir(folder.path, 0o700) != 0, errno != EEXIST { return String(cString: strerror(errno)) }
        var facts = stat()
        guard lstat(folder.path, &facts) == 0 else { return String(cString: strerror(errno)) }

        return facts.st_mode & S_IFMT == S_IFDIR ? nil : "it is a link or not a folder"
    }
}
