import Foundation

enum GatewayForward {
    static let hopByHop: Set<String> = [
        "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
        "te", "trailer", "trailers", "transfer-encoding", "upgrade",
        "host", "content-length",
    ]

    static func upstreamURL(for requestTarget: String, upstream: URL) -> URL? {
        guard let parsed = URLComponents(string: requestTarget) else { return nil }
        guard parsed.host == nil, parsed.scheme == nil else { return nil }
        guard parsed.percentEncodedPath.hasPrefix("/") else { return nil }
        var built = URLComponents()
        built.scheme = upstream.scheme
        built.host = upstream.host
        built.port = upstream.port
        built.percentEncodedPath = parsed.percentEncodedPath
        built.percentEncodedQuery = parsed.percentEncodedQuery
        return built.url
    }
}
