import Foundation
import NIOCore
import NIOHTTP1

final class CodexServiceHandshake: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let ready: EventLoopPromise<Void>

    init(ready: EventLoopPromise<Void>) {
        self.ready = ready
    }

    func channelActive(context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "localhost")
        headers.add(name: "Content-Length", value: "0")
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/", headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .head(let head) = unwrapInboundIn(data) else { return }
        ready.fail(CodexServiceError.handshake("status \(head.status.code)"))
        context.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        ready.fail(CodexServiceError.handshake(String(describing: error)))
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        ready.fail(CodexServiceError.closed)
        context.fireChannelInactive()
    }
}
