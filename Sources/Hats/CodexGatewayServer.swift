import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

enum CodexGatewayRecovery: Equatable {
    case retry(CodexGatewayLogin)
    case needsSignIn
    case unreachable
}

protocol CodexGatewayBroker: AnyObject {
    func unauthorized(_ refused: CodexGatewayLogin, then: @escaping (CodexGatewayRecovery) -> Void)
    func usageLimit(_ refused: CodexGatewayLogin, tried: Set<String>, then: @escaping (CodexGatewayLogin?) -> Void)
    func refusedAgain(_ login: CodexGatewayLogin)
}

final class CodexGatewayServer: @unchecked Sendable {
    let port: Int
    let secret: String
    let state: CodexGatewayState
    let broker: CodexGatewayBroker?
    let upstream: URL

    var holdWait = CodexHeldAnswer.maxWait
    var upstreamTimeout: TimeInterval = 600
    var maxBodyBytes = GatewayBodyLimit.maxBytes

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    private let channelLock = NSLock()
    private var storedChannel: Channel?

    init(
        port: Int,
        secret: String,
        state: CodexGatewayState,
        broker: CodexGatewayBroker?,
        upstream: URL = CodexGatewayPaths.upstream
    ) {
        self.port = port
        self.secret = secret
        self.state = state
        self.broker = broker
        self.upstream = upstream
    }

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

    var boundPort: Int? { channel?.localAddress?.port }

    var isServing: Bool { channel?.isActive ?? false }

    var baseURL: String { CodexGatewayPaths.baseURL(port: boundPort ?? port, secret: secret) }

    func start() throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 64)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [self] channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(CodexGatewayHandler(server: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
    }

    func stop() {
        try? channel?.close().wait()
        channel = nil
        try? group.syncShutdownGracefully()
    }

    var sessionsAtRiskText: String {
        (["\(SessionsAtRisk.readable) 1"] + state.threadIDs.map { "codex-thread \($0)" })
            .joined(separator: "\n") + "\n"
    }
}
