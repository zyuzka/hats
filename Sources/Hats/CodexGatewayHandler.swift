import Foundation
import NIOCore
import NIOHTTP1

final class CodexGatewayHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    static let threadHeader = "session-id"

    private let server: CodexGatewayServer
    private var head: HTTPRequestHead?
    private var body = Data()
    private var refusedBody = false
    private var exchange: CodexGatewayExchange?

    init(server: CodexGatewayServer) { self.server = server }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            self.head = head
            body = Data()
            refusedBody = !GatewayBodyLimit.allowsDeclaredLength(in: head.headers, limit: server.maxBodyBytes)
            if refusedBody { answer(context, .payloadTooLarge, CodexHeldAnswer.refusal("the request is too large")) }
        case .body(var buffer):
            guard !refusedBody else { return }
            let fits = GatewayBodyLimit.allows(
                buffered: body.count,
                incoming: buffer.readableBytes,
                limit: server.maxBodyBytes
            )
            guard fits else {
                refusedBody = true
                body = Data()
                answer(context, .payloadTooLarge, CodexHeldAnswer.refusal("the request is too large"))
                return
            }
            if let bytes = buffer.readBytes(length: buffer.readableBytes) { body.append(contentsOf: bytes) }
        case .end:
            defer {
                head = nil
                body = Data()
            }
            guard let head, !refusedBody else { return }
            handle(head, context: context)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        exchange?.cancel()
        exchange = nil
        context.fireChannelInactive()
    }

    private func handle(_ head: HTTPRequestHead, context: ChannelHandlerContext) {
        let route = CodexGatewayPaths.route(
            method: head.method.rawValue,
            uri: head.uri,
            secret: server.secret,
            upgrade: head.headers.first(name: "upgrade")
        )
        switch route {
        case .notFound:
            answer(context, .notFound, CodexHeldAnswer.refusal("no such path"))
        case .upgradeRequired:
            answer(context, .upgradeRequired, CodexHeldAnswer.refusal("this gateway speaks HTTP only"), close: true)
        case .sessionsAtRisk:
            answer(context, .ok, Data(server.sessionsAtRiskText.utf8), type: SessionsAtRisk.contentType)
        case .forward(let path, let query, _):
            let thread = head.headers.first(name: Self.threadHeader)
            if let thread, !thread.isEmpty { server.state.noteThread(thread) }
            let request = CodexGatewayExchange.Request(
                method: head.method.rawValue,
                path: path,
                query: query,
                headers: head.headers.map { ($0.name, $0.value) },
                body: body
            )
            let exchange = CodexGatewayExchange(channel: context.channel, server: server, request: request)
            self.exchange = exchange
            exchange.start()
        }
    }

    private func answer(
        _ context: ChannelHandlerContext,
        _ status: HTTPResponseStatus,
        _ body: Data,
        type: String = "application/json",
        close: Bool = false
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: type)
        headers.add(name: "Content-Length", value: String(body.count))
        if close { headers.add(name: "Connection", value: "close") }
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        let flushed = context.writeAndFlush(wrapOutboundOut(.end(nil)))
        guard close else { return }
        flushed.whenComplete { _ in context.close(promise: nil) }
    }
}
