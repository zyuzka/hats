import Foundation
import NIOPosix

protocol CodexLoginLink: AnyObject {
    func findAccountAfterRereadingLogin() throws -> String?
    func close()
}

final class CodexServiceLoginReread {
    typealias Log = (String, [String: String]) -> Void
    typealias Connect = (String) throws -> CodexLoginLink

    private let queue = DispatchQueue(label: "dev.tmk.hats.codex-login-reread")
    private let socket: URL
    private let connect: Connect
    private let log: Log

    init(codex: URL = CodexHome.real.url, connect: Connect? = nil, log: @escaping Log = Journal.log) {
        socket = codex.appendingPathComponent(CodexContinueRun.socketPath)
        self.connect = connect ?? { path in
            CodexServiceSession(client: try CodexServiceClient.connect(path: path, group: Self.group))
        }
        self.log = log
    }

    func reread(for hat: String, login: Data) {
        let expected = CodexAuth(data: login)?.identity?.email
        queue.async { [self] in rereadNow(for: hat, expecting: expected) }
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
            guard let account, account == expected else {
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

    private static let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}
