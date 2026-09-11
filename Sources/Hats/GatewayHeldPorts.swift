import Foundation

final class GatewayHeldPorts {
    static let shared = GatewayHeldPorts()

    private let lock = NSLock()
    private var ports: [Int] = []

    var current: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return ports
    }

    func replace(with ports: [Int]) {
        lock.lock()
        defer { lock.unlock() }
        self.ports = ports
    }
}
