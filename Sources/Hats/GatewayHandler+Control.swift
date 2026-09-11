import Foundation
import NIOCore
import NIOHTTP1

extension GatewayHandler {
    func isAControlPath(_ path: String) -> Bool {
        path == GatewayPaths.control || path == GatewayPaths.sessionsAtRisk
    }

    func answerControl(path: String, head: HTTPRequestHead, context: ChannelHandlerContext) {
        let host = head.headers.first(name: "host")
        guard GatewayPaths.isFromLoopback(
            host: host,
            boundTo: server.boundPort ?? server.port
        ) else {
            Journal.log("gateway.controlRefused", ["path": path, "host": host ?? "-"])
            let denied = GatewayErrorBody.describing(
                "this control path answers only the loopback host it listens on"
            )
            respond(context: context, status: .forbidden, body: denied)
            return
        }
        guard path == GatewayPaths.control else {
            answerSessionsAtRisk(context: context)
            return
        }
        respond(context: context, status: .ok, body: server.statusJSON())
    }
}
