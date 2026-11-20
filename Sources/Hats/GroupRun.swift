import Darwin
import Foundation

enum GroupRun {
    static let outputCap = 1 << 20
    static let graceSeconds: TimeInterval = 2
    static let pollMilliseconds: Int32 = 100

    static func getOutcome(of line: PluginCommandLine) -> PluginCommandOutcome {
        var output: [Int32] = [-1, -1]
        var errors: [Int32] = [-1, -1]
        guard pipe(&output) == 0 else { return PluginCommandOutcome(end: .notStarted("no pipe for its output")) }
        guard pipe(&errors) == 0 else {
            close(output[0])
            close(output[1])
            return PluginCommandOutcome(end: .notStarted("no pipe for its errors"))
        }
        let spawned = createChild(line, output: output[1], errors: errors[1])
        close(output[1])
        close(errors[1])
        switch spawned {
        case .failure(let refusal):
            close(output[0])
            close(errors[0])
            return PluginCommandOutcome(end: .notStarted(refusal.text))
        case .success(let pid):
            return getOutcome(
                ofChild: pid,
                reading: [
                    output[0],
                    errors[0],
                ],
                within: line.seconds
            )
        }
    }

    private static func getOutcome(
        ofChild pid: pid_t,
        reading streams: [Int32],
        within seconds: TimeInterval
    ) -> PluginCommandOutcome {
        let collected = GroupRunCollection()
        let drained = DispatchGroup()
        for (index, descriptor) in streams.enumerated() {
            drained.enter()
            DispatchQueue.global(qos: .utility).async {
                drain(
                    descriptor,
                    into: collected,
                    stream: index
                )
                close(descriptor)
                drained.leave()
            }
        }
        let reaped = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            collected.setEnd(getEnd(waitingFor: pid))
            reaped.signal()
        }
        let deadline = DispatchTime.now() + seconds
        let isReapedInTime = reaped.wait(timeout: deadline) == .success
        let isDrainedInTime = isReapedInTime && drained.wait(timeout: deadline) == .success
        if !isDrainedInTime {
            stopTheGroup(
                pid,
                reaped: reaped,
                collected: collected
            )
            if drained.wait(timeout: .now() + graceSeconds) == .timedOut { collected.abandon() }
        }

        return collected.createOutcome(
            isTimedOut: !isReapedInTime,
            isOutputLate: isReapedInTime && !isDrainedInTime
        )
    }

    private static func stopTheGroup(
        _ pid: pid_t,
        reaped: DispatchSemaphore,
        collected: GroupRunCollection
    ) {
        kill(-pid, SIGTERM)
        let hasEnded = collected.hasEnded || reaped.wait(timeout: .now() + graceSeconds) == .success
        kill(-pid, SIGKILL)
        guard !hasEnded else { return }
        _ = reaped.wait(timeout: .now() + graceSeconds)
    }

    private static func drain(
        _ descriptor: Int32,
        into collected: GroupRunCollection,
        stream: Int
    ) {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var watched = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        while !collected.isAbandoned {
            let ready = poll(&watched, 1, pollMilliseconds)
            if ready == 0 { continue }
            if ready < 0, errno == EINTR { continue }
            if ready < 0 { return }
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                collected.append(buffer[0..<count], to: stream)
                continue
            }
            if count < 0, errno == EINTR { continue }
            return
        }
    }

    private static func getEnd(waitingFor pid: pid_t) -> PluginCommandEnd {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 {
            guard errno == EINTR else { return .signalled(0) }
        }
        let signal = status & 0x7f
        guard signal != 0 else { return .exited((status >> 8) & 0xff) }

        return .signalled(signal)
    }
}
