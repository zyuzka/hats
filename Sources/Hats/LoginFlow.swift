import AppKit

final class LoginFlow {
    private let store: AccountStore
    private let world: LoginWatchWorld
    private let reader: LoginWatchReader
    private var automationAnswerIsSettled = false
    private var hasExplainedAutomation = false
    private var generations = WatchGeneration()

    var liveLoginMoved: (LiveIdentity) -> Void = { _ in Journal.log("login.moveIgnored") }
    var syncWithWorld: (Bool, CredentialClaim?) -> String? = { _, _ in nil }
    var lastTrouble: () -> String? = { nil }

    init(store: AccountStore, world: LoginWatchWorld? = nil) {
        self.store = store
        let world = world ?? .of(store: store)
        self.world = world
        self.reader = .of(world: world)
    }

    func duty() -> LoginWatchDuty {
        let duty = LoginWatchDuty.of(
            onDuty: generations.dutyHolder,
            pollAlive: generations.pollHolder,
            loginInFlight: Terminal.hasALoginInFlight(),
            scriptRunning: Terminal.isScriptRunning()
        )
        if duty.releasesTheWatch {
            generations.standDown(generations.dutyHolder)
            Terminal.removeScript()
            Journal.log("login.staleWatchReleased", ["loginScriptRunning": "no"])
        }
        return duty
    }

    func canStartALogin() -> Bool { !duty().isOnDuty }

    func begin(_ id: String, expecting: String?) throws {
        let identityBefore = store.liveIdentity()
        let configuration = try CLIState.configurationNow()
        let liveSlot = configuration.credentialService
        let pinned = configuration.source == .liveCLI
        let credentialBefore = store.liveSlotNow(inSlot: liveSlot)
        try store.beginLogin(id)
        awaitCompletion(
            expecting: expecting,
            identityBefore: identityBefore,
            credentialBefore: credentialBefore,
            inSlot: liveSlot,
            pinned: pinned
        )
    }

    private func ensureAutomationPermission() {
        guard !automationAnswerIsSettled else { return }
        let verdict = Automation.requestPermission(toAutomate: "com.apple.Terminal")
        automationAnswerIsSettled = Automation.isSettled(verdict)
        guard !hasExplainedAutomation,
              let explanation = Automation.explanation(for: verdict, appName: "Hats") else { return }
        hasExplainedAutomation = true
        HatDialogs.inform("The sign-in window will stay open", explanation)
    }

    private func askThenCloseTheLoginWindow(reporting report: ((WindowOutcome, Bool?) -> Void)? = nil) {
        ensureAutomationPermission()
        reader.closeTheWindow(then: report)
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
        run.closeTheLoginWindow = { [weak self] report in
            self?.askThenCloseTheLoginWindow(reporting: report)
        }
        run.start()
    }
}
