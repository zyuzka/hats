import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

enum CodexServiceError: Error, Equatable {
    case noService(String)
    case handshake(String)
    case refused(code: Int, message: String)
    case timedOut(String)
    case closed
    case badAnswer(String)

    var reason: String {
        switch self {
        case .noService: return "noService"
        case .handshake: return "handshake"
        case .refused: return "refused"
        case .timedOut: return "timedOut"
        case .closed: return "closed"
        case .badAnswer: return "badAnswer"
        }
    }

    var detail: String {
        switch self {
        case .noService(let text), .handshake(let text), .timedOut(let text), .badAnswer(let text):
            return text
        case .refused(let code, let message):
            return "\(code) \(message)"
        case .closed:
            return "the service closed the connection"
        }
    }
}

final class CodexServiceClient: @unchecked Sendable {
    static let clientName = "hats"
    static let maxFrame = 1 << 24

    private let channel: Channel
    private let rpc: CodexServiceRPC
    private let ids = NSLock()
    private var nextID = 1
    private init(channel: Channel, rpc: CodexServiceRPC) {
        self.channel = channel
        self.rpc = rpc
    }

    static func connect(
        path: String,
        group: EventLoopGroup,
        within: TimeAmount = .seconds(5),
        onRequest: @escaping (String) -> Void = { _ = $0 }
    ) throws -> CodexServiceClient {
        let loop = group.next()
        let ready = loop.makePromise(of: Void.self)
        let rpc = CodexServiceRPC(largestMessage: maxFrame, onRequest: onRequest)
        let handshake = CodexServiceHandshake(ready: ready)
        let upgrader = NIOWebSocketClientUpgrader(maxFrameSize: maxFrame) { channel, _ in
            channel.pipeline.addHandler(rpc).map { ready.succeed() }
        }
        let bootstrap = ClientBootstrap(group: loop)
            .connectTimeout(within)
            .channelInitializer { channel in
                let upgrade: NIOHTTPClientUpgradeSendableConfiguration = (
                    upgraders: [upgrader],
                    completionHandler: { context in
                        context.pipeline.removeHandler(handshake, promise: nil)
                    }
                )
                return channel.pipeline.addHTTPClientHandlers(withClientUpgrade: upgrade).flatMap {
                    channel.pipeline.addHandler(handshake)
                }
            }
        let channel: Channel
        do {
            channel = try bootstrap.connect(unixDomainSocketPath: path).wait()
        } catch {
            let failure = CodexServiceError.noService(String(describing: error))
            ready.fail(failure)
            throw failure
        }
        let timeout = loop.scheduleTask(in: within) {
            ready.fail(CodexServiceError.timedOut("handshake"))
        }
        do {
            try ready.futureResult.wait()
            timeout.cancel()
        } catch {
            timeout.cancel()
            channel.close(promise: nil)
            throw error as? CodexServiceError ?? CodexServiceError.handshake(String(describing: error))
        }
        let client = CodexServiceClient(channel: channel, rpc: rpc)
        do {
            try client.initialize(within: within)
        } catch {
            client.close()
            throw error
        }

        return client
    }

    func call(_ method: String, _ params: [String: Any], within: TimeAmount) throws -> [String: Any] {
        let id = takeID()
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
        let raw = try rpc.send(data, expecting: id, on: channel, within: within, name: method).wait()
        guard let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw CodexServiceError.badAnswer(method)
        }

        return object["result"] as? [String: Any] ?? [:]
    }

    func notify(_ method: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["method": method])
        try rpc.send(data, on: channel).wait()
    }

    func expectIdleAfterActive(of thread: String, within: TimeAmount) -> EventLoopFuture<Void> {
        rpc.expectIdleAfterActive(of: thread, on: channel, within: within)
    }

    func close() {
        channel.close(promise: nil)
    }

    private func initialize(within: TimeAmount) throws {
        let info: [String: Any] = ["name": Self.clientName, "title": NSNull(), "version": Self.version]
        let params: [String: Any] = ["clientInfo": info, "capabilities": ["experimentalApi": false]]
        _ = try call("initialize", params, within: within)
        try notify("initialized")
    }

    private func takeID() -> Int {
        ids.lock()
        defer { ids.unlock() }
        let id = nextID
        nextID += 1

        return id
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
