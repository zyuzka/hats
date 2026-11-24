import Foundation

protocol CodexLoginLink: AnyObject {
    func findAccountAfterRereadingLogin() throws -> CodexServiceAccount
    func close()
}

struct CodexServiceAccount: Equatable {
    let email: String?
    let owner: CodexOwner?

    static func of(_ result: [String: Any]) -> CodexServiceAccount {
        let workspace = (result["workspaceRouting"] as? [String: Any])?["chatgptAccountId"] as? String
        let owner = (result["userId"] as? String).flatMap { user in
            workspace.map { CodexOwner(userID: user, accountID: $0) }
        }

        return CodexServiceAccount(email: (result["account"] as? [String: Any])?["email"] as? String, owner: owner)
    }
}

final class CodexServiceLoginReread {
    typealias Log = (String, [String: String]) -> Void
    typealias Connect = (String) throws -> CodexLoginLink
    typealias Run = (@escaping () -> Void) -> Void
    typealias Expected = (email: String?, owner: CodexOwner?)

    private let socket: URL
    private let connect: Connect
    private let log: Log
    private let run: Run
    private let lock = NSLock()
    private var latest: (hat: String, expected: Expected)?

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
        let identity = CodexAuth(data: login)?.identity
        lock.lock()
        latest = (hat, (identity?.email, identity?.owner))
        lock.unlock()
        run { [self] in rereadTheLatest() }
    }

    func rereadNow(for hat: String, expecting expected: Expected) {
        let short = String(hat.prefix(8))
        guard FileManager.default.fileExists(atPath: socket.path) else {
            return log("codexService.loginReread.skipped", ["hat": short, "reason": "noService"])
        }
        do {
            let link = try connect(socket.path)
            defer { link.close() }
            let account = try link.findAccountAfterRereadingLogin()
            guard !hasANewerLogin() else { return }
            guard Self.isTheExpectedAccount(account, expected) else {
                return log("codexService.loginReread.otherAccount", [
                    "hat": short,
                    "account": account.email ?? "-",
                    "expected": expected.email ?? "-",
                ])
            }
            log("codexService.loginReread.done", ["hat": short, "account": account.email ?? "-"])
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

    private func hasANewerLogin() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return latest != nil
    }

    private static func isTheExpectedAccount(_ account: CodexServiceAccount, _ expected: Expected) -> Bool {
        if let owner = account.owner, let wanted = expected.owner { return owner == wanted }
        guard let email = account.email else { return false }
        guard let wanted = expected.email else { return true }

        return email.caseInsensitiveCompare(wanted) == .orderedSame
    }
}
