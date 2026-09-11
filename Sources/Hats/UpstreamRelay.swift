import Foundation
import NIOCore
import NIOHTTP1

final class UpstreamRelay: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let channel: Channel
    private let ledger: GatewayLedger
    private let path: String
    private let credential: String
    private let sessionID: String?
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var wroteHead = false

    init(channel: Channel, ledger: GatewayLedger, path: String, credential: String, session sessionID: String?) {
        self.channel = channel
        self.ledger = ledger
        self.path = path
        self.credential = credential
        self.sessionID = sessionID
    }

    func start(request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 600
        configuration.httpShouldUsePipelining = false
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        let task = session.dataTask(with: request)
        lock.lock()
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        let task = self.task
        let session = self.session
        self.session = nil
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }
        ledger.note(path: path, credential: credential, status: http.statusCode, session: sessionID)

        var headers = HTTPHeaders()
        for (name, value) in Self.relayedHeaders(from: http.allHeaderFields) {
            headers.add(name: name, value: value)
        }

        let head = HTTPResponseHead(
            version: .http1_1,
            status: HTTPResponseStatus(statusCode: http.statusCode),
            headers: headers
        )
        write(.head(head), flush: true)
        lock.lock()
        wroteHead = true
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        write(.body(.byteBuffer(buffer)), flush: true)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer {
            lock.lock()
            let finished = self.session
            self.session = nil
            lock.unlock()
            finished?.finishTasksAndInvalidate()
        }
        if let error, (error as? URLError)?.code == .cancelled { return }
        if let error {
            lock.lock()
            let headWasWritten = wroteHead
            lock.unlock()
            guard !headWasWritten else {
                ledger.noteTruncated(path: path, credential: credential, session: sessionID)
                hangUpWithoutEnding()
                return
            }
            reportUnreachable(error)
        }
        write(.end(nil), flush: true)
    }

    private func hangUpWithoutEnding() {
        channel.eventLoop.execute { [channel] in
            guard channel.isActive else { return }
            channel.close(promise: nil)
        }
    }

    private func reportUnreachable(_ error: Error) {
        ledger.note(path: path, credential: credential, status: 0, session: sessionID)
        let body = GatewayErrorBody.describing(error.localizedDescription)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: String(body.count))
        let head = HTTPResponseHead(
            version: .http1_1,
            status: .badGateway,
            headers: headers
        )
        write(.head(head))
        var buffer = channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        write(.body(.byteBuffer(buffer)))
    }

    private func write(_ part: HTTPServerResponsePart, flush: Bool = false) {
        channel.eventLoop.execute { [channel] in
            guard channel.isActive else { return }
            if flush {
                channel.writeAndFlush(part, promise: nil)
            } else {
                channel.write(part, promise: nil)
            }
        }
    }
}
