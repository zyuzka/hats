import Foundation
import NIOCore
import NIOHTTP1

final class CodexGatewayExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Request {
        let method: String
        let path: String
        let query: String?
        let headers: [(String, String)]
        let body: Data
    }

    enum Phase {
        case waiting
        case holding(HTTPURLResponse, Data)
        case deciding
        case streaming
        case done
    }

    static let replaced: Set<String> = ["authorization", "chatgpt-account-id"]
    static let turnState = "x-codex-turn-state"

    let channel: Channel
    let server: CodexGatewayServer
    let request: Request
    let queue: OperationQueue
    var session: URLSession?
    var task: URLSessionDataTask?
    var login: CodexGatewayLogin?
    var tried: Set<String> = []
    var retriedAfter401: Set<String> = []
    var phase = Phase.waiting
    var attempt = 0

    init(channel: Channel, server: CodexGatewayServer, request: Request) {
        self.channel = channel
        self.server = server
        self.request = request
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = server.upstreamTimeout
        configuration.httpShouldUsePipelining = false
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func start() {
        queue.addOperation { [self] in send(on: server.state.login) }
    }

    func cancel() {
        queue.addOperation { [self] in
            phase = .done
            task?.cancel()
            task = nil
            session?.invalidateAndCancel()
            session = nil
        }
    }

    func send(on login: CodexGatewayLogin?) {
        guard case .waiting = phase, let session else { return }
        guard let login else { return refuse(CodexHeldAnswer.nothingWorn) }
        let target = CodexGatewayPaths.upstreamURL(base: server.upstream, path: request.path, query: request.query)
        guard let target else {
            return refuse("the request could not be addressed")
        }
        self.login = login
        attempt += 1
        let task = session.dataTask(with: upstreamRequest(to: target, as: login))
        self.task = task
        task.resume()
    }

    func upstreamRequest(to target: URL, as login: CodexGatewayLogin) -> URLRequest {
        var built = URLRequest(url: target)
        built.httpMethod = request.method
        built.timeoutInterval = server.upstreamTimeout
        for (name, value) in request.headers {
            let lowered = name.lowercased()
            guard !GatewayForward.hopByHop.contains(lowered), !Self.replaced.contains(lowered) else { continue }
            if lowered == Self.turnState, !server.state.isTurnState(value, issuedUnder: login.hatID) { continue }
            built.addValue(value, forHTTPHeaderField: name)
        }
        built.setValue("Bearer " + login.accessToken, forHTTPHeaderField: "Authorization")
        built.setValue(login.accountID, forHTTPHeaderField: "chatgpt-account-id")
        if !request.body.isEmpty { built.httpBody = request.body }

        return built
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard dataTask === task, let http = response as? HTTPURLResponse, let login else {
            return completionHandler(.cancel)
        }
        noteWhatTheAnswerCarries(http, under: login)
        if CodexHeldAnswer.isHeld(http.statusCode) {
            phase = .holding(http, Data())
            let held = attempt
            DispatchQueue.global().asyncAfter(deadline: .now() + server.holdWait) { [weak self] in
                self?.queue.addOperation { self?.holdingRanOut(attempt: held) }
            }
        } else {
            writeHead(of: http)
            phase = .streaming
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask === task else { return }
        switch phase {
        case .holding(let http, let held):
            let grown = held + data
            phase = .holding(http, grown)
            if grown.count > CodexHeldAnswer.maxBytes { stopHolding(http, grown, why: "tooLarge") }
        case .streaming:
            writeBody(data)
        case .waiting, .deciding, .done:
            break
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task else { return }
        self.task = nil
        switch phase {
        case .holding(let http, let held):
            let whole = error == nil && !CodexHeldAnswer.isCutShort(http, held)
            if whole { decide(http, held) } else { stopHolding(http, held, why: "cutOff", isOver: true) }
        case .streaming:
            if error == nil { finish() } else { hangUp() }
        case .waiting:
            refuse("the upstream could not be reached", status: .badGateway)
        case .deciding, .done:
            break
        }
    }
}
