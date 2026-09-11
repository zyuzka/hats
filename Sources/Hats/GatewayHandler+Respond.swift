import Foundation
import NIOCore
import NIOHTTP1

extension GatewayHandler {
    func respond(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        body: Data,
        thenClose: Bool = false
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: String(body.count))
        if thenClose { headers.add(name: "Connection", value: "close") }
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        let flushed = context.writeAndFlush(wrapOutboundOut(.end(nil)))
        guard thenClose else { return }
        flushed.whenComplete { _ in context.close(promise: nil) }
    }
}
