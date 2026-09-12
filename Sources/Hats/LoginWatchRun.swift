import Foundation

struct WatchDutyControl {
    let isOnDuty: (Int) -> Bool
    let isTheCurrent: (Int) -> Bool
    let standDown: (Int) -> Void
    let stopPolling: (Int) -> Void
}

final class LoginWatchRun {
    let generation: Int
    let expecting: String?

    private let reader: LoginWatchReader
    let world: LoginWatchWorld
    let duty: WatchDutyControl
    private let watch: LoginWatch
    private let deadline: Date
    private let pinned: Bool

    var observedTheLogin = false
    var windowClosedAt: Date?
    private var sawTheSignInRunning = false
    private var watchedSlot: String
    private var watchedBefore: LiveSlotNow
    private var awaitingABaseline = false

    var liveLoginMoved: (LiveIdentity) -> Void = { _ in Journal.log("login.moveIgnored") }
    var syncWithWorld: (Bool, CredentialClaim?) -> String? = { _, _ in nil }
    var lastTrouble: () -> String? = { nil }
    var closeTheLoginWindow: () -> Void = { Journal.log("login.closeIgnored") }
    var signInSettled: () -> Void = { Journal.log("login.settledIgnored") }

    init(
        reader: LoginWatchReader,
        world: LoginWatchWorld,
        duty: WatchDutyControl,
        generation: Int,
        watch: LoginWatch,
        deadline: Date,
        expecting: String?,
        inSlot liveSlot: String,
        credentialBefore: LiveSlotNow,
        pinned: Bool
    ) {
        self.reader = reader
        self.world = world
        self.duty = duty
        self.generation = generation
        self.watch = watch
        self.deadline = deadline
        self.expecting = expecting
        self.watchedSlot = liveSlot
        self.watchedBefore = credentialBefore
        self.pinned = pinned
    }

    func start() { schedule() }

    private func isStillOurs() -> Bool {
        guard duty.isOnDuty(generation) else {
            Journal.log("login.watchSuperseded", ["expecting": expecting ?? "-"])
            return false
        }
        return true
    }

    private func schedule() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in tick() }
    }

    private func tick() {
        guard isStillOurs() else { return }
        reader.read(inSlot: watchedSlot) { [self] reading in
            guard isStillOurs() else { return }
            apply(reading)
        }
    }

    private func apply(_ reading: LoginWatchReading) {
        liveLoginMoved(reading.identity)
        if !pinned, let named = reading.resolvedSlot, named != watchedSlot {
            Journal.log("login.slotResolvedLate", ["was": watchedSlot, "now": named])
            watchedSlot = named
            awaitingABaseline = true
            return schedule()
        }
        if awaitingABaseline {
            watchedBefore = reading.slot
            awaitingABaseline = false
            return schedule()
        }
        let credentialMoved = LiveSlotNow.hasChanged(from: watchedBefore, to: reading.slot)
        let completed = watch.hasCompleted(identityNow: reading.identity, credentialMoved: credentialMoved)

        if !observedTheLogin, completed || windowClosedAt != nil {
            let claim = CredentialClaim(
                observed: reading.identity,
                slot: reading.slot,
                completed: completed,
                credentialMoved: credentialMoved
            )
            let reconciled = syncWithWorld(false, claim)
            if completed, let reconciled, watch.hasSettled(onReconciled: reconciled) {
                observedTheLogin = true
                signInSettled()
            }
        }

        if windowClosedAt == nil, hasTheLoginWindowClosed(reading, completed: completed) {
            windowClosedAt = Date()
        }

        let expired = WatchExpiry.hasExpired(now: Date(), deadline: deadline, windowClosedAt: windowClosedAt)

        guard !(observedTheLogin && windowClosedAt != nil), !expired else {
            finish()
            return
        }
        schedule()
    }

    private func hasTheLoginWindowClosed(_ reading: LoginWatchReading, completed: Bool) -> Bool {
        if reading.isDone {
            closeTheLoginWindow()
            return true
        }
        if reading.signInRunning == true { sawTheSignInRunning = true }
        guard LoginWatchDuty.hasTheSignInDiedWithoutFinishing(
            seenRunning: sawTheSignInRunning,
            loginInFlight: reading.loginInFlight
        ) else { return false }
        Journal.log("login.signInGone", ["completed": String(completed)])
        return true
    }
}
