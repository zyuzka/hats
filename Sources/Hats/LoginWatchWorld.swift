import Foundation

struct LoginWatchReading {
    let identity: LiveIdentity
    let slot: LiveSlotNow
    let resolvedSlot: String?
    let isDone: Bool
    let scriptRunning: Bool?
    let loginInFlight: Bool
}

struct LoginWatchWorld {
    var identity: () -> LiveIdentity
    var slot: (String) -> LiveSlotNow
    var resolvedSlot: () -> String?
    var isDone: () -> Bool
    var scriptRunning: () -> Bool?
    var loginInFlight: () -> Bool
    var closeTheWindow: () -> WindowOutcome
    var removeScript: () -> Void

    func read(inSlot liveSlot: String) -> LoginWatchReading {
        LoginWatchReading(
            identity: identity(),
            slot: slot(liveSlot),
            resolvedSlot: resolvedSlot(),
            isDone: isDone(),
            scriptRunning: scriptRunning(),
            loginInFlight: loginInFlight()
        )
    }

    static func of(store: AccountStore) -> LoginWatchWorld {
        LoginWatchWorld(
            identity: { store.liveIdentity() },
            slot: { store.liveSlotNow(inSlot: $0) },
            resolvedSlot: { (try? CLIState.configurationRemembered())?.credentialService },
            isDone: { Terminal.isDone },
            scriptRunning: { Terminal.isScriptRunning() },
            loginInFlight: { Terminal.hasALoginInFlight() },
            closeTheWindow: { TerminalWindow.closeLoginWindow(scriptName: Terminal.scriptName) },
            removeScript: { Terminal.removeScript() }
        )
    }
}

struct LoginWatchReader {
    let world: LoginWatchWorld
    let queue: DispatchQueue
    let closing: DispatchQueue

    static func of(world: LoginWatchWorld) -> LoginWatchReader {
        LoginWatchReader(
            world: world,
            queue: DispatchQueue(label: "dev.tmk.hats.login-watch"),
            closing: DispatchQueue(label: "dev.tmk.hats.login-window-close")
        )
    }

    func read(inSlot liveSlot: String, then apply: @escaping (LoginWatchReading) -> Void) {
        queue.async {
            let reading = world.read(inSlot: liveSlot)
            DispatchQueue.main.async { apply(reading) }
        }
    }

    func closeTheWindow(then report: ((WindowOutcome, Bool?) -> Void)?) {
        closing.async {
            let outcome = world.closeTheWindow()
            guard let report else { return }
            let stillRunning = world.scriptRunning()
            DispatchQueue.main.async { report(outcome, stillRunning) }
        }
    }
}
