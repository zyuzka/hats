import Darwin
import Foundation

enum LiveCLISessions {
    static let pathVariable = "PATH"
    static let wantedVariables = CLIState.configKeys.union([pathVariable])

    static func find(
        sessions: [Session]? = SessionDiscovery.everySessionThatHoldsAPort(),
        isTrusted: (Int32) -> Bool? = { TrustedCLI.isTheRealCLI(pid: $0) },
        reading: (Int32, Set<String>?) -> ProcessEnvironmentRead = { ProcessEnvironment.read(pid: $0, keeping: $1) },
        executable: (Int32) -> String? = { getExecutable(of: $0) }
    ) -> [LiveCLISession]? {
        guard let sessions else { return nil }
        var found: [LiveCLISession] = []
        for session in sessions {
            guard let trusted = isTrusted(session.pid) else { return nil }
            guard trusted else { continue }
            switch reading(session.pid, wantedVariables) {
            case .processGone:
                continue
            case .unreadable:
                return nil
            case .read(let environment):
                found.append(LiveCLISession(
                    pid: session.pid,
                    executable: executable(session.pid),
                    environment: environment
                ))
            }
        }

        return found
    }

    static func getExecutable(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }

        return String(cString: buffer)
    }
}
