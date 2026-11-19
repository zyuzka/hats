import Foundation
import NIOCore
import NIOWebSocket

final class CodexServiceRPC: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    static let statusChanged = "thread/status/changed"

    private let largestMessage: Int
    private let onRequest: (String) -> Void
    private var pending: [Int: EventLoopPromise<Data>] = [:]
    var waits: [CodexServiceIdleWait] = []
    private var message: ByteBuffer?
    var isClosed = false

    init(largestMessage: Int, onRequest: @escaping (String) -> Void) {
        self.largestMessage = largestMessage
        self.onRequest = onRequest
    }

    func send(_ data: Data, on channel: Channel) -> EventLoopFuture<Void> {
        channel.eventLoop.flatSubmit {
            self.write(data, on: channel)
        }
    }

    func send(
        _ data: Data,
        expecting id: Int,
        on channel: Channel,
        within: TimeAmount,
        name: String
    ) -> EventLoopFuture<Data> {
        let loop = channel.eventLoop
        let answer = loop.makePromise(of: Data.self)
        loop.execute {
            guard !self.isClosed else { return answer.fail(CodexServiceError.closed) }
            self.pending[id] = answer
            let timeout = loop.scheduleTask(in: within) {
                self.pending[id] = nil
                answer.fail(CodexServiceError.timedOut(name))
            }
            answer.futureResult.whenComplete { _ in timeout.cancel() }
            self.write(data, on: channel).whenFailure { error in
                self.pending[id] = nil
                answer.fail(error)
            }
        }

        return answer.futureResult
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, maskKey: .random(), data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .connectionClose:
            context.close(promise: nil)
        case .text, .binary:
            message = frame.unmaskedData
            finish(frame)
        case .continuation:
            var data = frame.unmaskedData
            message?.writeBuffer(&data)
            finish(frame)
        default:
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        isClosed = true
        let answers = pending.values
        pending = [:]
        answers.forEach { $0.fail(CodexServiceError.closed) }
        let idles = waits
        waits = []
        idles.forEach { $0.promise.fail(CodexServiceError.closed) }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    private func write(_ data: Data, on channel: Channel) -> EventLoopFuture<Void> {
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let frame = WebSocketFrame(fin: true, opcode: .text, maskKey: .random(), data: buffer)

        return channel.writeAndFlush(frame)
    }

    private func finish(_ frame: WebSocketFrame) {
        guard let size = message?.readableBytes else { return }
        guard size <= largestMessage else {
            message = nil
            return
        }
        guard frame.fin, var whole = message else { return }
        message = nil
        guard let bytes = whole.readBytes(length: whole.readableBytes) else { return }
        take(Data(bytes))
    }

    private func take(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let method = object["method"] as? String {
            if object["id"] != nil { return onRequest(method) }
            guard method == Self.statusChanged else { return }
            noteStatus(object["params"] as? [String: Any] ?? [:])
            return
        }
        guard let id = object["id"] as? Int, let answer = pending.removeValue(forKey: id) else { return }
        if let error = object["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? 0
            answer.fail(CodexServiceError.refused(code: code, message: error["message"] as? String ?? ""))
            return
        }
        answer.succeed(data)
    }
}
