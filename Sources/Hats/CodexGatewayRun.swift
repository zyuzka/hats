import Darwin
import Foundation

final class CodexGatewayRun: @unchecked Sendable {
    static let watchEveryByDefault: TimeInterval = 2

    let watchEvery: TimeInterval
    let state: CodexGatewayState
    let broker: CodexGatewayDesk
    let queue = DispatchQueue(label: "hats.codex-gateway", qos: .utility)
    private let lock = NSLock()
    private var storedServer: CodexGatewayServer?
    private var storedFailure: String?
    private var storedWrittenFor: String?
    private var storedNote: String?
    private var storedConfig: CodexConfigFile?
    private var storedInputs: CodexGatewayInputs?
    private var watcher: DispatchSourceTimer?
    private var lastStamp: [Int64]?

    init(broker: CodexGatewayDesk, watchEvery: TimeInterval = watchEveryByDefault) {
        precondition(watchEvery > 0, "a watch interval of zero or less would fire without pause")
        self.broker = broker
        self.watchEvery = watchEvery
        state = broker.state
    }

    func locked<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var server: CodexGatewayServer? { locked { storedServer } }
    var lastFailure: String? { locked { storedFailure } }

    var configWrittenFor: String? {
        get { locked { storedWrittenFor } }
        set { locked { storedWrittenFor = newValue } }
    }

    var configNote: String? {
        get { locked { storedNote } }
        set { locked { storedNote = newValue } }
    }

    var configFile: CodexConfigFile {
        get { locked { storedConfig } ?? CodexConfigFile(url: broker.desk.world.home.config) }
        set { locked { storedConfig = newValue } }
    }

    var lastInputs: CodexGatewayInputs? {
        get { locked { storedInputs } }
        set { locked { storedInputs = newValue } }
    }

    var isServing: Bool { server?.isServing ?? false }

    var servingPort: Int? { isServing ? server.map { $0.boundPort ?? $0.port } : nil }

    var baseURL: String? { isServing ? server?.baseURL : nil }

    var status: GatewayProcess.Status {
        if isServing { return .running }
        return lastFailure.map(GatewayProcess.Status.failed) ?? .notRunning
    }

    @discardableResult
    func start(port: Int, secret: String) -> GatewayProcess.Status {
        if let server, server.isServing, server.port == port, server.secret == secret { return .running }
        stop()
        state.forgetThreads()
        let candidate = CodexGatewayServer(port: port, secret: secret, state: state, broker: broker)
        do {
            try candidate.start()
        } catch {
            candidate.stop()
            locked { storedFailure = "the port \(port) could not be bound" }
            Journal.log("codexGateway.failed", ["port": String(port), "reason": error.localizedDescription])
            return status
        }
        locked {
            storedServer = candidate
            storedFailure = nil
        }
        Journal.log("codexGateway.started", ["port": String(port)])
        broker.noticeTheLiveFile()
        watchTheLiveFile()
        return .running
    }

    func stop() {
        let (timer, server): (DispatchSourceTimer?, CodexGatewayServer?) = locked {
            defer {
                watcher = nil
                lastStamp = nil
                storedServer = nil
            }
            return (watcher, storedServer)
        }
        timer?.cancel()
        guard let server else { return }
        server.stop()
        Journal.log("codexGateway.stopped", ["port": String(server.boundPort ?? server.port)])
    }

    private func watchTheLiveFile() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + watchEvery, repeating: watchEvery)
        let path = broker.desk.world.home.auth.path
        timer.setEventHandler { [weak self, weak timer] in
            guard let self, let timer, self.locked({ self.watcher === timer }) else { return }
            let stamp = Self.stamp(of: path)
            let moved: Bool = self.locked {
                guard self.watcher === timer, stamp != self.lastStamp else { return false }
                self.lastStamp = stamp
                return true
            }
            if moved { self.broker.noticeTheLiveFile() }
        }
        let stamp = Self.stamp(of: path)
        locked {
            lastStamp = stamp
            watcher = timer
        }
        timer.resume()
    }

    static func stamp(of path: String) -> [Int64]? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return [
            Int64(info.st_ino),
            Int64(info.st_size),
            Int64(info.st_mtimespec.tv_sec),
            Int64(info.st_mtimespec.tv_nsec),
        ]
    }
}
