import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

final class NIOTestListener: @unchecked Sendable {
    struct Request {
        let path: String
        let headers: [String: String]
        let body: String
    }

    enum Answer {
        case fixed(status: Int, headers: [String: String], body: String)
        case stream(chunks: [String], gap: TimeInterval)
        case stalled(seconds: TimeInterval)
        case stallsAfter(chunks: [String])
    }

    private let handler = Locked<((Request) -> Answer)?>(nil)

    var onRequest: ((Request) -> Answer)? {
        get { handler.value }
        set { handler.value = newValue }
    }

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?
    private let clientsGone = Locked(0)

    var disconnects: Int { clientsGone.value }

    var port: Int { channel?.localAddress?.port ?? 0 }

    func start() throws {
        channel = try ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [self] channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(Handler(listener: self))
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .wait()
    }

    func stop() {
        try? channel?.close().wait()
        channel = nil
        try? group.syncShutdownGracefully()
    }

    fileprivate func answer(for request: Request) -> Answer {
        return handler.value?(request) ?? .fixed(status: 200, headers: [:], body: "{}")
    }

    fileprivate func clientWentAway() {
        clientsGone.mutate { $0 += 1 }
    }

    private final class Handler: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart

        private let listener: NIOTestListener
        private var head: HTTPRequestHead?
        private var body = ""

        init(listener: NIOTestListener) { self.listener = listener }

        func channelInactive(context: ChannelHandlerContext) {
            listener.clientWentAway()
            context.fireChannelInactive()
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            switch unwrapInboundIn(data) {
            case .head(let head):
                self.head = head
                body = ""
            case .body(var buffer):
                body += buffer.readString(length: buffer.readableBytes) ?? ""
            case .end:
                guard let head else { return }
                var headers: [String: String] = [:]
                for header in head.headers { headers[header.name.lowercased()] = header.value }
                let request = Request(path: String(head.uri.split(separator: "?").first ?? ""),
                                      headers: headers, body: body)
                reply(to: listener.answer(for: request), context: context)
                self.head = nil
            }
        }

        private func reply(to answer: Answer, context: ChannelHandlerContext) {
            switch answer {
            case .fixed(let status, let headers, let body):
                var response = HTTPHeaders()
                for (name, value) in headers { response.add(name: name, value: value) }
                response.add(name: "Content-Length", value: String(body.utf8.count))
                write(context: context, status: status, headers: response, body: body,
                      end: true)
            case .stalled(let seconds):
                let channel = context.channel
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                    channel.eventLoop.execute {
                        let head = HTTPResponseHead(version: .http1_1, status: .ok,
                                                    headers: ["Content-Length": "0"])
                        channel.write(HTTPServerResponsePart.head(head), promise: nil)
                        channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                    }
                }
            case .stallsAfter(let chunks):
                var response = HTTPHeaders()
                response.add(name: "Content-Type", value: "text/event-stream")
                let head = HTTPResponseHead(
                    version: .http1_1,
                    status: HTTPResponseStatus(statusCode: 200),
                    headers: response
                )
                context.writeAndFlush(wrapOutboundOut(.head(head)), promise: nil)
                for chunk in chunks {
                    var buffer = context.channel.allocator.buffer(capacity: chunk.utf8.count)
                    buffer.writeString(chunk)
                    context.writeAndFlush(
                        wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }
            case .stream(let chunks, let gap):
                var response = HTTPHeaders()
                response.add(name: "Content-Type", value: "text/event-stream")
                let head = HTTPResponseHead(
                    version: .http1_1,
                    status: HTTPResponseStatus(statusCode: 200),
                    headers: response
                )
                context.writeAndFlush(wrapOutboundOut(.head(head)), promise: nil)
                let channel = context.channel
                DispatchQueue.global().async { [self] in
                    for chunk in chunks {
                        var buffer = channel.allocator.buffer(capacity: chunk.utf8.count)
                        buffer.writeString(chunk)
                        channel.eventLoop.execute {
                            channel.writeAndFlush(
                                HTTPServerResponsePart.body(.byteBuffer(buffer)),
                                promise: nil)
                        }
                        Thread.sleep(forTimeInterval: gap)
                    }
                    channel.eventLoop.execute {
                        channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
                    }
                }
            }
        }

        private func write(context: ChannelHandlerContext, status: Int,
                           headers: HTTPHeaders, body: String, end: Bool) {
            let head = HTTPResponseHead(
                version: .http1_1,
                status: HTTPResponseStatus(statusCode: status),
                headers: headers
            )
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
            buffer.writeString(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            if end { context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil) }
        }
    }
}
