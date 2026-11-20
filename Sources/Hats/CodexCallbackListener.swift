import Darwin
import Foundation

final class CodexCallbackListener {
    let port: Int
    private let socket: Int32
    private let queue = DispatchQueue(label: "hats.codex.callback")
    private var source: DispatchSourceRead?
    private let lock = NSLock()
    private var closed = false

    private init(socket: Int32, port: Int) {
        self.socket = socket
        self.port = port
    }

    static func open(ports: [Int], answer: @escaping (String) -> CodexHTTPAnswer) throws -> CodexCallbackListener {
        for port in ports {
            switch bound(port) {
            case .success(let socket):
                let listener = CodexCallbackListener(socket: socket, port: port)
                listener.start(answer)
                return listener
            case .failure(let error) where error == .inUse:
                continue
            case .failure(let error):
                throw CodexError.listenerFailed(error.text)
            }
        }
        throw CodexError.portsTaken(ports)
    }

    deinit { close() }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        source?.cancel()
    }

    private func start(_ answer: @escaping (String) -> CodexHTTPAnswer) {
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: queue)
        let socket = socket
        source.setEventHandler { [weak self] in
            let client = Darwin.accept(socket, nil, nil)
            guard client >= 0 else { return }
            self?.serve(client, answer)
        }
        source.setCancelHandler { Darwin.close(socket) }
        self.source = source
        source.resume()
    }

    private func serve(_ client: Int32, _ answer: (String) -> CodexHTTPAnswer) {
        defer { Darwin.close(client) }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        guard let target = Self.requestTarget(readingFrom: client) else { return }
        Self.write(answer(target), to: client)
    }

    static func requestTarget(readingFrom client: Int32) -> String? {
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let end = Data("\r\n\r\n".utf8)
        while received.count < 16_384, received.range(of: end) == nil {
            let count = Darwin.read(client, &buffer, buffer.count)
            guard count > 0 else { break }
            received.append(contentsOf: buffer[0..<count])
        }
        guard let head = String(data: received, encoding: .utf8)?.components(separatedBy: "\r\n").first else {
            return nil
        }
        let parts = head.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }

        return String(parts[1])
    }

    static func write(_ answer: CodexHTTPAnswer, to client: Int32) {
        var head = "HTTP/1.1 \(answer.status) \(reason(answer.status))\r\n"
        for (name, value) in answer.headers.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        head += "Content-Length: \(answer.body.count)\r\nConnection: close\r\n\r\n"
        let bytes = Data(head.utf8) + answer.body
        bytes.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let count = Darwin.write(client, raw.baseAddress?.advanced(by: sent), raw.count - sent)
                guard count > 0 else { return }
                sent += count
            }
        }
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 302: return "Found"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        default: return "Status"
        }
    }

    struct BindError: Error, Equatable {
        let text: String
        static let inUse = BindError(text: "in use")
    }

    static func bound(_ port: Int) -> Result<Int32, BindError> {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return .failure(BindError(text: String(cString: strerror(errno)))) }
        var reuse: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0, Darwin.listen(socket, 16) == 0 else {
            let code = errno
            Darwin.close(socket)
            return .failure(code == EADDRINUSE ? .inUse : BindError(text: String(cString: strerror(code))))
        }

        return .success(socket)
    }
}
