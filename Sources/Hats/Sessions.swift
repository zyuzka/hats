import Foundation

struct Session: Equatable {
    let pid: Int32
    let elapsed: String
    let isInteractive: Bool
    var route: SessionRoute = .unknown

    static func parsedExecutables(psOutput: String) -> [Int32: String] {
        var executables: [Int32: String] = [:]
        for line in psOutput.split(separator: "\n") {
            let row = line.trimmingCharacters(in: .whitespaces)
            guard let gap = row.firstIndex(of: " "),
                  let pid = Int32(row[row.startIndex..<gap]) else { continue }
            let path = row[row.index(after: gap)...].trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            executables[pid] = path
        }
        return executables
    }

    static func parse(psLine: String, executables: [Int32: String]) -> Session? {
        let fields = psLine.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 3, let pid = Int32(fields[0]) else { return nil }

        guard let executable = executables[pid],
              URL(fileURLWithPath: executable).lastPathComponent == "claude" else { return nil }

        let command = fields.dropFirst(2).joined(separator: " ")
        let oneShot = command.contains(" -p ") || command.hasSuffix(" -p")
            || command.contains("--print")
        return Session(pid: pid, elapsed: String(fields[1]), isInteractive: !oneShot)
    }
}

final class RememberedFor<Value> {
    private let lock = NSLock()
    private var held: Value?
    private var keptAt: ContinuousClock.Instant?

    func value(within window: Duration) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let held, let keptAt, keptAt.duration(to: .now) < window else { return nil }
        return held
    }

    func keep(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        held = value
        keptAt = .now
    }

    func forget() {
        lock.lock()
        defer { lock.unlock() }
        held = nil
        keptAt = nil
    }
}

typealias RecentSessions = RememberedFor<[Session]>

extension RememberedFor where Value == [Session] {
    static let shared = RecentSessions()
    static let window: Duration = .seconds(1)
}

enum SessionDiscovery {
    static let readerBudget: TimeInterval = 1

    static func everySessionSeenRecently(
        within window: Duration = RecentSessions.window,
        memory: RecentSessions = .shared,
        sweeping: () -> [Session]? = {
            everySessionThatHoldsAPort(
                readingTheProcessTable: { ProcessTable.read($0, within: readerBudget) }
            )
        }
    ) -> [Session]? {
        if let remembered = memory.value(within: window) { return remembered }
        guard let swept = sweeping() else { return nil }
        memory.keep(swept)
        return swept
    }

    static func everySessionThatHoldsAPort(
        readingTheProcessTable read: ([String]) -> String? = { ProcessTable.read($0) }
    ) -> [Session]? {
        guard let executables = read(["-eo", "pid=,comm="]),
              let commands = read(["-eo", "pid=,etime=,command="]) else { return nil }
        let byPID = Session.parsedExecutables(psOutput: executables)
        return commands
            .split(separator: "\n")
            .compactMap { line -> Session? in
                Session.parse(
                    psLine: String(line).trimmingCharacters(in: .whitespaces),
                    executables: byPID
                )
            }
            .map(routed)
    }

    private static func routed(_ session: Session) -> Session {
        var routed = session
        let environment = ProcessEnvironment.read(pid: session.pid,
                                                  keeping: [ShellEnvironment.baseURLName])
        routed.route = SessionRoute.of(environment: environment.values)
        return routed
    }
}

enum ProcessTable {
    static func output(data: Data,
                       reason: Process.TerminationReason,
                       status: Int32) -> String? {
        guard reason == .exit, status == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static let budget: TimeInterval = 5

    private static let outcomeLock = NSLock()
    private static var timingOut = false

    @discardableResult
    static func noteOutcome(timedOut: Bool, within budget: TimeInterval) -> String? {
        outcomeLock.lock()
        defer { outcomeLock.unlock() }
        guard timingOut != timedOut else { return nil }
        timingOut = timedOut
        let event = timedOut ? "processTable.timedOut" : "processTable.answeredAgain"
        Journal.log(event, timedOut ? ["seconds": String(format: "%g", budget)] : [:])

        return event
    }

    static func read(_ arguments: [String],
                     within budget: TimeInterval = budget,
                     running executable: String = "/bin/ps") -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }

        let lock = NSLock()
        var answer: String?
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard exited.wait(timeout: .now() + budget) == .success else { return }
            let read = output(data: data,
                              reason: process.terminationReason,
                              status: process.terminationStatus)
            lock.lock()
            answer = read
            lock.unlock()
            done.signal()
        }
        if done.wait(timeout: .now() + budget) == .timedOut {
            process.terminate()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            Self.noteOutcome(timedOut: true, within: budget)
            return nil
        }
        Self.noteOutcome(timedOut: false, within: budget)
        lock.lock()
        defer { lock.unlock() }
        return answer
    }
}
