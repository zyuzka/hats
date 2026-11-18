import XCTest
@testable import Hats

final class FakeCodexBroker: CodexGatewayBroker {
    let limitCalls = Locked<[Set<String>]>([])
    let unauthorizedCalls = Locked<[String]>([])
    let refusedAgainCalls = Locked<[String]>([])
    var onLimit: (CodexGatewayLogin, Set<String>) -> CodexGatewayLogin? = { _, _ in nil }
    var onUnauthorized: (CodexGatewayLogin) -> CodexGatewayRecovery = { _ in .needsSignIn }
    var delay: TimeInterval = 0

    func unauthorized(_ refused: CodexGatewayLogin, then: @escaping (CodexGatewayRecovery) -> Void) {
        unauthorizedCalls.mutate { $0.append(refused.hatID) }
        let next = onUnauthorized(refused)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { then(next) }
    }

    func usageLimit(_ refused: CodexGatewayLogin, tried: Set<String>, then: @escaping (CodexGatewayLogin?) -> Void) {
        limitCalls.mutate { $0.append(tried) }
        let next = onLimit(refused, tried)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { then(next) }
    }

    func refusedAgain(_ login: CodexGatewayLogin) {
        refusedAgainCalls.mutate { $0.append(login.hatID) }
    }
}

struct CodexGatewayReply {
    let status: Int
    let body: String
    let headers: [AnyHashable: Any]
}

class CodexGatewayTestCase: XCTestCase {
    let secret = String(repeating: "5e", count: 32)
    let state = CodexGatewayState()
    let broker = FakeCodexBroker()
    let seen = Locked<[NIOTestListener.Request]>([])
    let workLogin = CodexFixture.login(CodexFixture.work, refresh: "work-1")
    let personalLogin = CodexFixture.login(CodexFixture.personal, refresh: "personal-1")
    var upstream: NIOTestListener!
    var gateway: CodexGatewayServer!
    var answers: (NIOTestListener.Request) -> NIOTestListener.Answer = { _ in
        .fixed(status: 200, headers: [:], body: #"{"ok":true}"#)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        upstream = NIOTestListener()
        upstream.onRequest = { [unowned self] request in
            seen.mutate { $0.append(request) }
            return answers(request)
        }
        try upstream.start()
        gateway = CodexGatewayServer(
            port: 0,
            secret: secret,
            state: state,
            broker: broker,
            upstream: URL(string: "http://127.0.0.1:\(upstream.port)/backend-api/codex")!
        )
        try gateway.start()
    }

    override func tearDown() {
        gateway?.stop()
        upstream?.stop()
        super.tearDown()
    }

    var port: Int { gateway.boundPort ?? 0 }

    func token(_ login: Data) -> String { CodexAuth(data: login)?.accessToken ?? "-" }

    @discardableResult
    func wear(_ hat: String, _ login: Data) -> CodexGatewayLogin? { state.wear(hatID: hat, auth: login) }

    func ask(
        _ path: String = "codex/responses",
        method: String = "POST",
        secret: String? = nil,
        headers: [String: String] = [:]
    ) -> CodexGatewayReply {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(secret ?? self.secret)/\(path)")!)
        request.httpMethod = method
        if method == "POST" { request.httpBody = Data(#"{"input":[]}"#.utf8) }
        request.setValue("Bearer codex-own-token", forHTTPHeaderField: "Authorization")
        request.setValue("acct-codex-own", forHTTPHeaderField: "chatgpt-account-id")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        var reply = CodexGatewayReply(status: 0, body: "", headers: [:])
        let waiter = expectation(description: path)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let http = response as? HTTPURLResponse
            reply = CodexGatewayReply(
                status: http?.statusCode ?? 0,
                body: data.map { String(decoding: $0, as: UTF8.self) } ?? "",
                headers: http?.allHeaderFields ?? [:]
            )
            waiter.fulfill()
        }.resume()
        wait(for: [waiter], timeout: 20)
        return reply
    }

    var lastSeen: NIOTestListener.Request? { seen.value.last }

    static func limitBody(_ type: String = CodexHeldAnswer.usageLimit) -> String {
        #"{"error":{"type":"\#(type)","message":"You've hit your usage limit."}}"#
    }
}
