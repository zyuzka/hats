import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

final class FakeCodexService: @unchecked Sendable {
    enum Reply {
        case result([String: Any])
        case error(code: Int, message: String)
        case fragmented([String: Any])
        case silence
    }

    struct Call {
        let method: String
        let params: [String: Any]
    }

    let path: String
    private let folder: URL
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?
    private let calls = Locked<[Call]>([])
    private let pongs = Locked<[String]>([])
    private let client = Locked<Channel?>(nil)

    var pongsReceived: [String] { pongs.value }

    func ping(_ text: String) {
        guard let channel = client.value else { return }
        var buffer = channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        channel.writeAndFlush(WebSocketFrame(fin: true, opcode: .ping, data: buffer), promise: nil)
    }
    private let script = Locked<((Call) -> (Reply, [[String: Any]]))?>(nil)

    var received: [Call] { calls.value }

    var onCall: ((Call) -> (Reply, [[String: Any]]))? {
        get { script.value }
        set { script.value = newValue }
    }

    init() {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hcs-\(UUID().uuidString.prefix(8))")
        path = folder.appendingPathComponent("s.sock").path
    }

    func start(upgrades: Bool = true) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let upgrader = NIOWebSocketServerUpgrader(
            maxFrameSize: 1 << 20,
            shouldUpgrade: { channel, _ in channel.eventLoop.makeSucceededFuture(upgrades ? HTTPHeaders() : nil) },
            upgradePipelineHandler: { [self] channel, _ in
                client.value = channel
                return channel.pipeline.addHandler(Handler(service: self))
            }
        )
        channel = try ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in })
                ).flatMap { upgrades ? channel.eventLoop.makeSucceededVoidFuture() : channel.pipeline.addHandler(Refuser()) }
            }
            .bind(unixDomainSocketPath: path)
            .wait()
    }

    func stop() {
        try? channel?.close().wait()
        try? group.syncShutdownGracefully()
        try? FileManager.default.removeItem(at: folder)
    }

    fileprivate func notePong(_ text: String) {
        pongs.mutate { $0.append(text) }
    }

    fileprivate func answer(_ call: Call) -> (Reply, [[String: Any]]) {
        calls.mutate { $0.append(call) }
        return script.value?(call) ?? (.result([:]), [])
    }

    private final class Refuser: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            guard case .end = unwrapInboundIn(data) else { return }
            let head = HTTPResponseHead(version: .http1_1, status: .forbidden, headers: ["Content-Length": "0"])
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }

    private final class Handler: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = WebSocketFrame
        typealias OutboundOut = WebSocketFrame

        private let service: FakeCodexService

        init(service: FakeCodexService) { self.service = service }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let frame = unwrapInboundIn(data)
            if frame.opcode == .pong {
                var pong = frame.unmaskedData
                service.notePong(pong.readString(length: pong.readableBytes) ?? "")
                return
            }
            guard frame.opcode == .text else { return }
            var buffer = frame.unmaskedData
            guard let bytes = buffer.readBytes(length: buffer.readableBytes),
                  let object = try? JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any],
                  let method = object["method"] as? String
            else { return }
            let (reply, after) = service.answer(Call(method: method, params: object["params"] as? [String: Any] ?? [:]))
            guard let id = object["id"] else { return }
            switch reply {
            case .result(let result):
                send(["id": id, "result": result], context: context)
            case .error(let code, let message):
                send(["id": id, "error": ["code": code, "message": message]], context: context)
            case .fragmented(let result):
                sendInTwo(["id": id, "result": result], channel: context.channel)
            case .silence:
                break
            }
            let channel = context.channel
            for (index, note) in after.enumerated() {
                channel.eventLoop.scheduleTask(in: .milliseconds(Int64(50 * (index + 1)))) {
                    self.send(note, channel: channel)
                }
            }
        }

        private func sendInTwo(_ object: [String: Any], channel: Channel) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            let half = data.count / 2
            var first = channel.allocator.buffer(capacity: half)
            first.writeBytes(data.prefix(half))
            var second = channel.allocator.buffer(capacity: data.count - half)
            second.writeBytes(data.suffix(from: half))
            channel.write(WebSocketFrame(fin: false, opcode: .text, data: first), promise: nil)
            channel.writeAndFlush(WebSocketFrame(fin: true, opcode: .continuation, data: second), promise: nil)
        }

        private func send(_ object: [String: Any], context: ChannelHandlerContext) {
            send(object, channel: context.channel)
        }

        private func send(_ object: [String: Any], channel: Channel) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            channel.writeAndFlush(WebSocketFrame(fin: true, opcode: .text, data: buffer), promise: nil)
        }
    }
}

extension FakeCodexService {
    static func status(_ thread: String, _ type: String) -> [String: Any] {
        ["method": "thread/status/changed", "params": ["threadId": thread, "status": ["type": type]]]
    }

    static func thread(_ id: String, status: String, ephemeral: Bool = false, path: Any = "/r.jsonl") -> [String: Any] {
        ["thread": [
            "id": id, "sessionId": id, "ephemeral": ephemeral, "path": path,
            "parentThreadId": NSNull(), "status": ["type": status],
        ]]
    }
}
