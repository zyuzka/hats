import Foundation

enum SessionRoute: Equatable {
    case unknown
    case direct
    case pointedAt(String)

    static func of(environment: [String: String]?) -> SessionRoute {
        guard let environment else { return .unknown }
        let value = environment[ShellEnvironment.baseURLName]?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? .direct : .pointedAt(value)
    }

    func isThrough(gatewayAt baseURL: String) -> Bool {
        guard case .pointedAt(let value) = self else { return false }
        return Self.comparable(value) == Self.comparable(baseURL)
    }

    func isThrough(anyOf baseURLs: [String]) -> Bool {
        baseURLs.contains { isThrough(gatewayAt: $0) }
    }

    static let loopbackNames: Set<String> = ["localhost", "localhost.", "::1", "::ffff:127.0.0.1"]

    static func isTheLoopbackHost(_ host: String) -> Bool {
        if loopbackNames.contains(host) { return true }
        var address = in_addr()
        guard inet_aton(host, &address) == 1 else { return false }
        return address.s_addr == in_addr_t(INADDR_LOOPBACK).bigEndian
    }

    func isOnLoopback(port: Int) -> Bool {
        guard case .pointedAt(let value) = self,
              let url = URL(string: value.trimmingCharacters(in: .whitespaces)),
              url.port == port,
              let host = url.host?.lowercased() else { return false }
        return Self.isTheLoopbackHost(host)
    }

    private static func comparable(_ url: String) -> String {
        var text = url.lowercased()
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
