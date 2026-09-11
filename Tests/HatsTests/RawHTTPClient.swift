import Foundation
import NIOCore
import NIOPosix

enum RawHTTPClient {
    struct TimedOut: Error, CustomStringConvertible {
        let received: String

        var description: String {
            "no complete response within the timeout; \(received.utf8.count) bytes arrived"
        }
    }

    final class Connection {
        private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        private let channel: Channel
        private let collector = Collector()
        private var isShutDown = false

        init(port: Int) throws {
            channel = try ClientBootstrap(group: group)
                .channelInitializer { [collector] channel in
                    channel.pipeline.addHandler(collector)
                }
                .connect(host: "127.0.0.1", port: port)
                .wait()
        }

        func send(_ request: String) throws {
            var buffer = channel.allocator.buffer(capacity: request.utf8.count)
            buffer.writeString(request)
            try channel.writeAndFlush(buffer).wait()
        }

        func waitUntilTheBodyStarts(timeout: TimeInterval = 10) throws {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline, !collector.bodyHasStarted {
                Thread.sleep(forTimeInterval: 0.02)
            }
            guard collector.bodyHasStarted else { throw TimedOut(received: collector.text) }
        }

        var received: String { collector.text }

        func waitUntilTheServerHangsUp(timeout: TimeInterval = 10) throws {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline, !collector.hasClosed {
                Thread.sleep(forTimeInterval: 0.02)
            }
            guard collector.hasClosed else { throw TimedOut(received: collector.text) }
        }

        func hangUp() {
            guard !isShutDown else { return }
            isShutDown = true
            try? channel.close().wait()
            try? group.syncShutdownGracefully()
        }

        deinit {
            hangUp()
        }
    }

    static func send(_ request: String, toPort port: Int,
                     timeout: TimeInterval = 10) throws -> String {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let collector = Collector()
        let channel = try ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandler(collector)
            }
            .connect(host: "127.0.0.1", port: port)
            .wait()

        var buffer = channel.allocator.buffer(capacity: request.utf8.count)
        buffer.writeString(request)
        try channel.writeAndFlush(buffer).wait()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !collector.sawEnd {
            Thread.sleep(forTimeInterval: 0.05)
        }
        try? channel.close().wait()
        guard collector.sawEnd else { throw TimedOut(received: collector.text) }

        return collector.text
    }

    private final class Collector: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = ByteBuffer

        private let lock = NSLock()
        private var received = ""
        private var closed = false

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return received
        }

        var hasClosed: Bool {
            lock.lock()
            defer { lock.unlock() }
            return closed
        }

        var bodyHasStarted: Bool {
            guard let split = text.range(of: "\r\n\r\n") else { return false }
            return !text[split.upperBound...].isEmpty
        }

        var sawEnd: Bool {
            lock.lock()
            let whole = received
            let isClosed = closed
            lock.unlock()
            guard let split = whole.range(of: "\r\n\r\n") else { return false }
            let head = whole[..<split.lowerBound].lowercased()
            let body = whole[split.upperBound...]
            if let declared = Self.declaredLength(in: head) { return body.utf8.count >= declared }
            if head.contains("transfer-encoding: chunked") { return body.hasSuffix("0\r\n\r\n") }

            return isClosed
        }

        private static func declaredLength(in head: String) -> Int? {
            for line in head.split(separator: "\r\n") where line.hasPrefix("content-length:") {
                return Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
            }
            return nil
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            var buffer = unwrapInboundIn(data)
            guard let chunk = buffer.readString(length: buffer.readableBytes) else { return }
            lock.lock()
            received += chunk
            lock.unlock()
        }

        func channelInactive(context: ChannelHandlerContext) {
            lock.lock()
            closed = true
            lock.unlock()
            context.fireChannelInactive()
        }
    }
}
