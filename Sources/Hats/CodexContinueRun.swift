import Foundation
import NIOCore
import NIOPosix

final class CodexContinueRun {
    struct Wish: Equatable {
        var isOn: Bool
        var warnPercent: Int?
        var savePercent: Int?
    }

    typealias Log = (String, [String: String]) -> Void
    typealias Connect = (String) throws -> CodexServiceLink

    static let socketPath = "app-server-control/app-server-control.sock"

    private let queue = DispatchQueue(label: "dev.tmk.hats.codex-continue")
    private let folder: URL
    private let socket: URL
    private let notes: URL
    private let lookEvery: TimeInterval
    private let connect: Connect
    private let log: Log
    private let now: () -> Date
    private var wish: Wish?
    private var memory = CodexContinueMemory()
    private var lastLine = NoteOnChange()
    private var timer: DispatchSourceTimer?

    init(
        root: URL = StateDirectory.url,
        codex: URL = CodexHome.real.url,
        notes: URL = CodexNotes.folder,
        lookEvery: TimeInterval = 5,
        connect: Connect? = nil,
        log: @escaping Log = Journal.log,
        now: @escaping () -> Date = Date.init
    ) {
        folder = root.appendingPathComponent(CodexCompactLimitSync.folderName)
        socket = codex.appendingPathComponent(Self.socketPath)
        self.notes = notes
        self.lookEvery = lookEvery
        self.connect = connect ?? { path in
            try CodexContinueRun.connectToTheService(path) { log("codexContinue.serviceRequest", ["method": $0]) }
        }
        self.log = log
        self.now = now
    }

    deinit {
        timer?.cancel()
    }

    func configure(_ wish: Wish) {
        queue.async { [self] in
            self.wish = wish
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + lookEvery, repeating: lookEvery)
            timer.setEventHandler { [weak self] in self?.look() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            wish = nil
        }
    }

    func lookNow() {
        queue.sync { look() }
    }

    private func look() {
        guard let wish, wish.isOn else { return }
        let scan = CodexContinue.scan(folder, now: now())
        let due = memory.due(scan, warn: wish.warnPercent, save: wish.savePercent, now: now())
        for mark in due where CodexContinue.isFresh(mark, now: now()) {
            guard CodexContinue.isUnchanged(mark, in: folder, now: now()) else { continue }
            act(on: mark)
        }
    }

    private func act(on mark: CodexWindowMark) {
        guard FileManager.default.fileExists(atPath: socket.path) else {
            return write("codexContinue.skipped", reason: "noService", mark: nil)
        }
        guard CodexNotes.hasNote(for: mark.session, in: notes) else {
            memory.noteHandled(mark)
            return write("codexContinue.skipped", reason: "noNote", mark: mark)
        }
        let link: CodexServiceLink
        do {
            link = try connect(socket.path)
        } catch {
            let detail = (error as? CodexServiceError)?.detail ?? String(describing: error)
            guard case CodexServiceError.noService = error else {
                memory.noteHandled(mark)
                return write("codexContinue.failed", reason: "connectFailed", mark: mark, detail: detail)
            }
            return write("codexContinue.skipped", reason: "noService", mark: nil, detail: detail)
        }
        defer { link.close() }
        let (outcome, compacted) = CodexContinueSteps.run(mark.session, on: link)
        if compacted { memory.noteActed(mark) } else { memory.noteHandled(mark) }
        switch outcome {
        case .done:
            lastLine.clear()
            log("codexContinue.done", ["session": mark.session, "percent": String(mark.percent)])
        case .skipped(let reason, let detail):
            write("codexContinue.skipped", reason: reason, mark: mark, detail: detail)
        case .failed(let reason, let detail):
            write("codexContinue.failed", reason: reason, mark: mark, detail: detail)
        }
    }

    private func write(_ name: String, reason: String, mark: CodexWindowMark?, detail: String? = nil) {
        guard lastLine.shouldWrite("\(name) \(reason) \(mark?.session ?? "")") else { return }
        var details = ["reason": reason]
        if let mark {
            details["session"] = mark.session
            details["percent"] = String(mark.percent)
        }
        if let detail { details["detail"] = detail }
        log(name, details)
    }

    static let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    private static func connectToTheService(
        _ path: String,
        onRequest: @escaping (String) -> Void
    ) throws -> CodexServiceLink {
        CodexServiceSession(client: try CodexServiceClient.connect(path: path, group: group, onRequest: onRequest))
    }
}
