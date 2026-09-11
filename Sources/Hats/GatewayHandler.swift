import Foundation
import NIOCore
import NIOHTTP1

final class GatewayHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    let server: GatewayServer
    private let upstream: URL
    private var head: HTTPRequestHead?
    private var body = Data()
    private var relay: UpstreamRelay?
    private var refusedBody = false

    init(server: GatewayServer, upstream: URL) {
        self.server = server
        self.upstream = upstream
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            self.head = head
            body = Data()
            refusedBody = false
            if !GatewayBodyLimit.allowsDeclaredLength(in: head.headers, limit: server.maxBodyBytes) {
                refuseTheBody(context: context)
            }
        case .body(var buffer):
            guard !refusedBody else { return }
            guard GatewayBodyLimit.allows(
                buffered: body.count,
                incoming: buffer.readableBytes,
                limit: server.maxBodyBytes
            ) else {
                refuseTheBody(context: context)
                return
            }
            if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                body.append(contentsOf: bytes)
            }
        case .end:
            defer {
                self.head = nil
                body = Data()
            }
            guard let head, !refusedBody else { return }
            handle(head: head, body: body, context: context)
        }
    }

    private func refuseTheBody(context: ChannelHandlerContext) {
        refusedBody = true
        body = Data()
        let reason = GatewayErrorBody.describing("the request body is larger than the gateway accepts")
        respond(context: context, status: .payloadTooLarge, body: reason, thenClose: true)
    }

    func channelInactive(context: ChannelHandlerContext) {
        relay?.cancel()
        relay = nil
        context.fireChannelInactive()
    }

    private func handle(head: HTTPRequestHead, body: Data, context: ChannelHandlerContext) {
        let path = String(head.uri.split(separator: "?").first ?? "")

        if isAControlPath(path) {
            answerControl(path: path, head: head, context: context)
            return
        }

        let authorization = head.headers.first(name: "authorization")
        let facts = GatewayRequestFacts(
            path: path,
            credential: GatewayCredential.fingerprint(authorization),
            session: head.headers.first(name: GatewayPaths.sessionHeader)
        )

        if let refusal = server.refusal, refusal.shouldRefuse(
            path: facts.path,
            credential: facts.credential,
            session: facts.session
        ) {
            server.ledger.note(
                path: facts.path,
                credential: facts.credential,
                status: 401,
                session: facts.session
            )
            respond(context: context, status: .unauthorized, body: GatewayErrorBody.refusal)
            return
        }

        forward(head: head, body: body, facts: facts, context: context)
    }

    private func forward(
        head: HTTPRequestHead,
        body: Data,
        facts: GatewayRequestFacts,
        context: ChannelHandlerContext
    ) {
        guard let target = GatewayForward.upstreamURL(for: head.uri, upstream: upstream) else {
            server.ledger.noteRefusedTarget(
                path: facts.path,
                credential: facts.credential,
                session: facts.session
            )
            let reason = GatewayErrorBody.describing("the request URI could not be resolved")
            respond(context: context, status: .badGateway, body: reason)
            return
        }

        var request = URLRequest(url: target)
        request.httpMethod = head.method.rawValue
        request.timeoutInterval = server.upstreamTimeout
        for header in head.headers where !GatewayForward.hopByHop.contains(header.name.lowercased()) {
            request.addValue(header.value, forHTTPHeaderField: header.name)
        }
        if !body.isEmpty { request.httpBody = body }

        let relay = UpstreamRelay(
            channel: context.channel,
            ledger: server.ledger,
            path: facts.path,
            credential: facts.credential,
            session: facts.session
        )
        self.relay = relay
        relay.start(request: request)
    }

}
