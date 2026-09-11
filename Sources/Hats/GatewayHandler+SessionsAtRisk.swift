import Foundation
import NIOCore
import NIOHTTP1

extension GatewayHandler {
    static let sessionsQueue = DispatchQueue(label: "hats.gateway-sessions-at-risk")

    func answerSessionsAtRisk(context: ChannelHandlerContext) {
        let channel = context.channel
        let allocator = channel.allocator
        let ports = [server.boundPort ?? server.port] + server.portsTheAppWouldTakeDown()
        let read = server.sessionsReader
        Self.sessionsQueue.async {
            let body = SessionsAtRisk.body(ports: ports, sessions: read())
            channel.eventLoop.execute {
                guard channel.isActive else { return }
                var headers = HTTPHeaders()
                headers.add(name: "Content-Type", value: SessionsAtRisk.contentType)
                headers.add(name: "Content-Length", value: String(body.count))
                let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
                var buffer = allocator.buffer(capacity: body.count)
                buffer.writeBytes(body)
                channel.write(HTTPServerResponsePart.head(head), promise: nil)
                channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
                channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
            }
        }
    }
}
