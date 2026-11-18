import Foundation

struct CodexSignInWorld {
    var ports: [Int] = CodexOAuth.ports
    var waitLimit: TimeInterval = CodexOAuth.waitLimit
    var random: (Int) -> Data = CodexOAuth.systemRandom
    var now: () -> Date = Date.init
    var open: (URL) throws -> Void
    var send: (URLRequest) -> (status: Int, body: Data?)
    var after: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    var onMain: (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
}

final class CodexSignInRun {
    enum Ending: Equatable {
        case signedIn(Data)
        case refused(String)
        case cancelled
        case timedOut
    }

    var ended: (Ending) -> Void = { _ in Journal.log("codex.signIn.endIgnored") }

    private let world: CodexSignInWorld
    private let secrets: CodexOAuth.Secrets
    private var listener: CodexCallbackListener?
    private var redirectURI = ""
    private let lock = NSLock()
    private var ending: Ending?

    init(world: CodexSignInWorld) {
        self.world = world
        secrets = CodexOAuth.secrets(random: world.random)
    }

    var port: Int? { listener?.port }

    var isInFlight: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ending == nil
    }

    func start() throws {
        let listener = try CodexCallbackListener.open(ports: world.ports) { [weak self] target in
            self?.answer(target) ?? .plain(404, "Not Found")
        }
        self.listener = listener
        redirectURI = CodexOAuth.redirectURI(port: listener.port)
        guard let url = CodexOAuth.authorizeURL(redirectURI: redirectURI, secrets: secrets) else {
            listener.close()
            throw CodexError.listenerFailed("the sign-in address could not be built")
        }
        Journal.log("codex.signIn.listening", ["port": String(listener.port)])
        do {
            try world.open(url)
        } catch {
            listener.close()
            throw CodexError.browserNotOpened(error.localizedDescription)
        }
        world.after(world.waitLimit) { [weak self] in _ = self?.hasEnded(with: .timedOut) }
    }

    func cancel() { _ = hasEnded(with: .cancelled) }

    func answer(_ target: String) -> CodexHTTPAnswer {
        switch CodexCallback.judge(target: target, state: secrets.state) {
        case .successPage:
            return .page(200, "Signed in to Codex. Hats has the login; you can close this tab.")
        case .notFound:
            return .plain(404, "Not Found")
        case .stateMismatch:
            Journal.log("codex.signIn.stateMismatch")
            return .plain(400, "State mismatch")
        case .refused(let why):
            guard isInFlight else { return .plain(404, "Not Found") }
            _ = hasEnded(with: .refused(why))
            return .page(200, "Sign-in could not be completed: \(why)")
        case .code(let code):
            guard isInFlight else { return .plain(404, "Not Found") }
            return exchange(code)
        }
    }

    private func exchange(_ code: String) -> CodexHTTPAnswer {
        let request = CodexOAuth.exchangeRequest(code: code, redirectURI: redirectURI, verifier: secrets.verifier)
        let reply = world.send(request)
        switch CodexOAuth.exchangeOutcome(status: reply.status, body: reply.body) {
        case .failed(let why):
            _ = hasEnded(with: .refused(why))
            return .page(200, "Sign-in could not be completed: \(why)")
        case let .tokens(id, access, refresh):
            let auth = CodexAuth.signedIn(
                idToken: id,
                accessToken: access,
                refreshToken: refresh,
                loginOwnerID: CodexJWT.base64URLEncoded(world.random(32)),
                at: world.now()
            )
            guard let data = try? auth.data() else {
                _ = hasEnded(with: .refused("the login could not be encoded"))
                return .page(200, "Sign-in could not be completed.")
            }
            guard hasEnded(with: .signedIn(data), keepListening: true) else {
                return .page(200, "Hats stopped waiting before this sign-in finished, so nothing was stored. "
                    + "Start the sign-in again in Hats.")
            }
            return .toTheSuccessPage
        }
    }

    private func hasEnded(with outcome: Ending, keepListening: Bool = false) -> Bool {
        lock.lock()
        guard ending == nil else {
            lock.unlock()
            return false
        }
        ending = outcome
        lock.unlock()
        let listener = listener
        if keepListening {
            world.after(10) { listener?.close() }
        } else {
            listener?.close()
        }
        Journal.log("codex.signIn.ended", ["how": Self.journalName(outcome)])
        world.onMain { [weak self] in self?.ended(outcome) }

        return true
    }

    static func journalName(_ ending: Ending) -> String {
        switch ending {
        case .signedIn: return "signedIn"
        case .refused(let why): return "refused: \(why)"
        case .cancelled: return "cancelled"
        case .timedOut: return "timedOut"
        }
    }
}
