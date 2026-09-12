import Foundation

struct LoginWatchReading {
    let identity: LiveIdentity
    let slot: LiveSlotNow
    let resolvedSlot: String?
    let isDone: Bool
    let signInRunning: Bool?
    let loginInFlight: Bool
}

struct LoginWatchWorld {
    var identity: () -> LiveIdentity
    var slot: (String) -> LiveSlotNow
    var resolvedSlot: () -> String?
    var isDone: () -> Bool
    var signInRunning: () -> Bool?
    var loginInFlight: () -> Bool

    func read(inSlot liveSlot: String) -> LoginWatchReading {
        LoginWatchReading(
            identity: identity(),
            slot: slot(liveSlot),
            resolvedSlot: resolvedSlot(),
            isDone: isDone(),
            signInRunning: signInRunning(),
            loginInFlight: loginInFlight()
        )
    }

    static func of(store: AccountStore, signIn: @escaping () -> SignInRun?) -> LoginWatchWorld {
        LoginWatchWorld(
            identity: { store.liveIdentity() },
            slot: { store.liveSlotNow(inSlot: $0) },
            resolvedSlot: { (try? CLIState.configurationRemembered())?.credentialService },
            isDone: { signIn()?.hasSignedIn ?? false },
            signInRunning: { signIn()?.isRunning },
            loginInFlight: { signIn()?.isInFlight ?? false }
        )
    }
}

struct LoginWatchReader {
    let world: LoginWatchWorld
    let queue: DispatchQueue

    static func of(world: LoginWatchWorld) -> LoginWatchReader {
        LoginWatchReader(
            world: world,
            queue: DispatchQueue(label: "dev.tmk.hats.login-watch")
        )
    }

    func read(inSlot liveSlot: String, then apply: @escaping (LoginWatchReading) -> Void) {
        queue.async {
            let reading = world.read(inSlot: liveSlot)
            DispatchQueue.main.async { apply(reading) }
        }
    }
}
