import AppKit

final class SignInInFlight {
    var run: SignInRun?
}

final class LoginFlow {
    private let store: AccountStore
    private let world: LoginWatchWorld
    private let reader: LoginWatchReader
    private let inFlight: SignInInFlight
    private let window = SignInWindow()
    private var model: SignInModel?
    private var afterTheSignInStops: (() -> Void)?
    private var generations = WatchGeneration()

    var liveLoginMoved: (LiveIdentity) -> Void = { _ in Journal.log("login.moveIgnored") }
    var syncWithWorld: (Bool, CredentialClaim?) -> String? = { _, _ in nil }
    var lastTrouble: () -> String? = { nil }

    init(store: AccountStore, world injected: LoginWatchWorld? = nil) {
        let inFlight = SignInInFlight()
        self.store = store
        self.inFlight = inFlight
        let world = injected ?? .of(store: store, signIn: { inFlight.run })
        self.world = world
        self.reader = .of(world: world)
    }

    func duty() -> LoginWatchDuty {
        let duty = LoginWatchDuty.of(
            onDuty: generations.dutyHolder,
            pollAlive: generations.pollHolder,
            loginInFlight: world.loginInFlight(),
            signInRunning: world.signInRunning()
        )
        if duty.releasesTheWatch {
            generations.standDown(generations.dutyHolder)
            Journal.log("login.staleWatchReleased", ["signInRunning": "no"])
        }
        return duty
    }

    func canStartALogin() -> Bool { !world.loginInFlight() }

    func showTheSignInWindow() {
        guard let model else { return }
        window.show(model)
    }

    func abandonTheSignIn(then resume: @escaping () -> Void) {
        guard let run = inFlight.run, run.isInFlight else { return resume() }
        afterTheSignInStops = resume
        Journal.log("signIn.abandonAsked")
        run.cancel()
    }

    func begin(_ id: String, expecting: String?) throws {
        let identityBefore = store.liveIdentity()
        let configuration = try CLIState.configurationNow()
        let liveSlot = configuration.credentialService
        let pinned = configuration.source == .liveCLI
        let credentialBefore = store.liveSlotNow(inSlot: liveSlot)
        let command = try store.beginLogin(id)
        try openTheSignIn(command, expecting: expecting)
        awaitCompletion(
            expecting: expecting,
            identityBefore: identityBefore,
            credentialBefore: credentialBefore,
            inSlot: liveSlot,
            pinned: pinned
        )
    }

    private func openTheSignIn(_ command: SignInCommand, expecting: String?) throws {
        let run = SignInRun()
        let model = SignInModel(title: HatsCopy.signingInAs(expecting))
        model.submit = { [weak run, weak model] code in
            run?.send(code)
            model?.code = ""
        }
        model.stop = { [weak self] in self?.cancelTheSignIn() }
        run.changed = { [weak model] transcript in model?.transcript = transcript }
        run.ended = { [weak self] ending in self?.theSignInEnded(ending) }
        window.wasClosedByAPerson = { [weak self] in self?.cancelTheSignIn() }
        inFlight.run = run
        self.model = model
        window.show(model)
        try run.start(command)
    }

    private func cancelTheSignIn() {
        guard let run = inFlight.run, run.isInFlight else { return window.close() }
        run.cancel()
    }

    private func theSignInEnded(_ ending: SignInRun.Ending) {
        if let resume = afterTheSignInStops {
            afterTheSignInStops = nil
            window.close()
            model = nil
            return resume()
        }
        switch ending {
        case .signedIn, .cancelled:
            window.close()
            model = nil
        case .failed(let status):
            model?.trouble = HatsCopy.signInFailed(status)
        }
    }

    private func awaitCompletion(
        expecting: String?,
        identityBefore: LiveIdentity,
        credentialBefore: LiveSlotNow,
        inSlot liveSlot: String,
        pinned: Bool
    ) {
        let run = LoginWatchRun(
            reader: reader,
            world: world,
            duty: WatchDutyControl(
                isOnDuty: { [weak self] in self?.generations.isOnDuty($0) ?? false },
                isTheCurrent: { [weak self] in self?.generations.isTheCurrent($0) ?? false },
                standDown: { [weak self] in self?.generations.standDown($0) },
                stopPolling: { [weak self] in self?.generations.stopPolling($0) }
            ),
            generation: generations.take(),
            watch: LoginWatch(expecting: expecting, identityBefore: identityBefore),
            deadline: Date().addingTimeInterval(15 * 60),
            expecting: expecting,
            inSlot: liveSlot,
            credentialBefore: credentialBefore,
            pinned: pinned
        )
        run.liveLoginMoved = { [weak self] identity in self?.liveLoginMoved(identity) }
        run.syncWithWorld = { [weak self] reporting, claim in
            guard let self else { return nil }
            return syncWithWorld(reporting, claim)
        }
        run.lastTrouble = { [weak self] in
            guard let self else { return nil }
            return lastTrouble()
        }
        run.closeTheLoginWindow = { [weak self] in self?.cancelTheSignIn() }
        run.start()
    }
}
