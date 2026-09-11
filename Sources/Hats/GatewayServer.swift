import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

final class GatewayServer {
    let port: Int
    let refusal: GatewayRefusal?
    let ledger = GatewayLedger()

    private let group: MultiThreadedEventLoopGroup
    private let channelLock = NSLock()
    private var storedChannel: Channel?
    private var channel: Channel? {
        get {
            channelLock.lock()
            defer { channelLock.unlock() }
            return storedChannel
        }
        set {
            channelLock.lock()
            defer { channelLock.unlock() }
            storedChannel = newValue
        }
    }
    private var watcher: DispatchSourceTimer?
    private let upstream: URL
    private let accountReader: () -> String?
    let sessionsReader: () -> [Session]?
    let portsTheAppWouldTakeDown: () -> [Int]

    static let defaultUpstream = URL(string: "https://api.anthropic.com")
        ?? URL(fileURLWithPath: "/")

    var watchInterval: TimeInterval = 0.5
    var maxBodyBytes = GatewayBodyLimit.maxBytes
    var upstreamTimeout: TimeInterval = 600

    init(
        port: Int,
        refusal: GatewayRefusal?,
        upstream: URL = GatewayServer.defaultUpstream,
        accountReader: @escaping () -> String? = GatewayServer.liveAccountAddress,
        sessionsReader: @escaping () -> [Session]? = { SessionDiscovery.everySessionSeenRecently() },
        portsTheAppWouldTakeDown: @escaping () -> [Int] = { GatewayHeldPorts.shared.current }
    ) {
        self.port = port
        self.refusal = refusal
        self.upstream = upstream
        self.accountReader = accountReader
        self.sessionsReader = sessionsReader
        self.portsTheAppWouldTakeDown = portsTheAppWouldTakeDown
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    }

    var boundPort: Int? { channel?.localAddress?.port }

    func start() throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 64)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [self] channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    let handler = GatewayHandler(server: self, upstream: self.upstream)
                    return channel.pipeline.addHandler(handler)
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
        startWatchingTheAccount()
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        try? channel?.close().wait()
        channel = nil
        try? group.syncShutdownGracefully()
    }

    var isServing: Bool { channel?.isActive ?? false }

    static func liveAccountAddress() -> String? {
        guard let configuration = try? CLIState.configurationRemembered(),
              let url = configuration.stateFile().url else { return nil }
        return CLIState.readIdentity(at: url)?.email
    }

    private func startWatchingTheAccount() {
        guard let refusal else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + watchInterval, repeating: watchInterval)
        let read = accountReader
        timer.setEventHandler {
            refusal.hasSwitched(to: read())
        }
        timer.resume()
        watcher = timer
    }

    func statusJSON() -> Data {
        var report: [String: Any] = ledger.snapshot()
        report["served_by"] = GatewayPaths.marker
        if let refusal {
            let switching = refusal.snapshot()
            var block: [String: Any] = [
                "account": switching.account ?? NSNull(),
                "refusals": switching.refusals,
            ]
            if let seconds = switching.secondsSinceSwitch {
                block["since_switch"] = [
                    "switched_to": switching.switchedTo ?? "",
                    "seconds_since_switch": seconds,
                    "settling": switching.settling,
                    "sessions_moved": switching.sessionsMoved,
                ]
            } else {
                block["since_switch"] = NSNull()
            }
            report["switching"] = block
        }
        let encoded = try? JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        return encoded ?? Data("{}".utf8)
    }
}
