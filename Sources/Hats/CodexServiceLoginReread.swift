import Foundation

protocol CodexLoginLink: AnyObject {
    func findAccountAfterRereadingLogin() throws -> String?
    func close()
}

final class CodexServiceLoginReread {
    typealias Log = (String, [String: String]) -> Void
    typealias Connect = (String) throws -> CodexLoginLink
    typealias Run = (@escaping () -> Void) -> Void

    private let socket: URL
    private let connect: Connect
    private let log: Log
    private let run: Run
    private let lock = NSLock()
    private var latest: (hat: String, expected: String?)?

    init(
        codex: URL = CodexHome.real.url,
        connect: Connect? = nil,
        log: @escaping Log = Journal.log,
        run: Run? = nil
    ) {
        socket = codex.appendingPathComponent(CodexContinueRun.socketPath)
        self.connect = connect ?? { path in
            CodexServiceSession(client: try CodexServiceClient.connect(path: path, group: CodexContinueRun.group))
        }
        self.log = log
        let queue = DispatchQueue(label: "dev.tmk.hats.codex-login-reread")
        self.run = run ?? { queue.async(execute: $0) }
    }

    func reread(for hat: String, login: Data) {
        lock.lock()
        latest = (hat, CodexAuth(data: login)?.identity?.email)
        lock.unlock()
        run { [self] in rereadTheLatest() }
    }

    func rereadNow(for hat: String, expecting expected: String?) {
        let short = String(hat.prefix(8))
        guard FileManager.default.fileExists(atPath: socket.path) else {
            return log("codexService.loginReread.skipped", ["hat": short, "reason": "noService"])
        }
        do {
            let link = try connect(socket.path)
            defer { link.close() }
            let account = try link.findAccountAfterRereadingLogin()
            guard let account, Self.isTheExpectedAccount(account, expected) else {
                return log("codexService.loginReread.otherAccount", [
                    "hat": short,
                    "account": account ?? "-",
                    "expected": expected ?? "-",
                ])
            }
            log("codexService.loginReread.done", ["hat": short, "account": account])
        } catch CodexServiceError.noService(let detail) {
            log("codexService.loginReread.skipped", ["hat": short, "reason": "noService", "detail": detail])
        } catch {
            let detail = (error as? CodexServiceError).map { "\($0.reason): \($0.detail)" } ?? String(describing: error)
            log("codexService.loginReread.failed", ["hat": short, "detail": detail])
        }
    }

    private func rereadTheLatest() {
        lock.lock()
        let next = latest
        latest = nil
        lock.unlock()
        guard let next else { return }
        rereadNow(for: next.hat, expecting: next.expected)
    }

    private static func isTheExpectedAccount(_ account: String, _ expected: String?) -> Bool {
        guard let expected else { return true }

        return account.caseInsensitiveCompare(expected) == .orderedSame
    }
}
