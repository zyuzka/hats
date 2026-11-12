import Foundation

final class GroupRunCollection {
    private let lock = NSLock()
    private var streams = [Data(), Data()]
    private var isCut = false
    private var wasAbandoned = false
    private var end: PluginCommandEnd?

    var isAbandoned: Bool {
        lock.lock()
        defer { lock.unlock() }
        return wasAbandoned
    }

    func abandon() {
        lock.lock()
        defer { lock.unlock() }
        wasAbandoned = true
    }

    var hasEnded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return end != nil
    }

    func append(_ bytes: ArraySlice<UInt8>, to stream: Int) {
        lock.lock()
        defer { lock.unlock() }
        let room = GroupRun.outputCap - streams[stream].count
        if bytes.count > room { isCut = true }
        streams[stream].append(contentsOf: bytes.prefix(max(room, 0)))
    }

    func setEnd(_ value: PluginCommandEnd) {
        lock.lock()
        defer { lock.unlock() }
        end = value
    }

    func createOutcome(isTimedOut: Bool, isOutputLate: Bool) -> PluginCommandOutcome {
        lock.lock()
        defer { lock.unlock() }
        let finalEnd: PluginCommandEnd = isTimedOut ? .timedOut : (end ?? .timedOut)

        return PluginCommandOutcome(
            end: finalEnd,
            stdout: streams[0],
            stderr: streams[1],
            isTruncated: isCut || isOutputLate || wasAbandoned
        )
    }
}
