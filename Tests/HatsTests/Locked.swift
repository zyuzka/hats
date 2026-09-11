import Foundation

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }

    @discardableResult
    func mutate<Result>(_ change: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return change(&stored)
    }
}
