import Foundation
import NIOCore
import NIOHTTP1

extension CodexGatewayExchange {
    func refuse(_ message: String, status: HTTPResponseStatus = .badRequest) {
        let body = CodexHeldAnswer.refusal(message)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: String(body.count))
        write(.head(HTTPResponseHead(version: .http1_1, status: status, headers: headers)))
        writeBody(body)
        finish()
    }

    func writeHead(of http: HTTPURLResponse, length: Int? = nil) {
        var headers = HTTPHeaders()
        for (name, value) in UpstreamRelay.relayedHeaders(from: http.allHeaderFields) {
            headers.add(name: name, value: value)
        }
        if let length { headers.add(name: "Content-Length", value: String(length)) }
        write(.head(HTTPResponseHead(
            version: .http1_1,
            status: HTTPResponseStatus(statusCode: http.statusCode),
            headers: headers
        )))
    }

    func writeBody(_ data: Data) {
        guard !data.isEmpty else { return }
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        write(.body(.byteBuffer(buffer)))
    }

    func finish() {
        phase = .done
        write(.end(nil))
        session?.finishTasksAndInvalidate()
        session = nil
    }

    func hangUp() {
        phase = .done
        session?.invalidateAndCancel()
        session = nil
        channel.eventLoop.execute { [channel] in
            guard channel.isActive else { return }
            channel.close(promise: nil)
        }
    }

    func write(_ part: HTTPServerResponsePart) {
        channel.eventLoop.execute { [channel] in
            guard channel.isActive else { return }
            channel.writeAndFlush(part, promise: nil)
        }
    }
}
