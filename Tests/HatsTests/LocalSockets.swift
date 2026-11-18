import Darwin
import Foundation
@testable import Hats

enum LocalSockets {
    static func freePorts(_ count: Int) -> [Int] {
        (0..<count).map { _ in
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, length) }
            }
            _ = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.getsockname(fd, $0, &length) }
            }
            close(fd)
            return Int(UInt16(bigEndian: address.sin_port))
        }
    }

    static func get(_ target: String, port: Int) throws -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw CodexError.listenerFailed("connect \(errno)") }
        let request = "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"
        _ = request.withCString { write(fd, $0, strlen($0)) }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            received.append(contentsOf: buffer[0..<count])
        }

        return String(data: received, encoding: .utf8) ?? ""
    }
}
