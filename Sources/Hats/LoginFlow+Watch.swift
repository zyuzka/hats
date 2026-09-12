import Foundation

extension LoginFlow {
    func awaitCompletion(
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
        run.signInSettled = { [weak self] in self?.signInSettled() }
        run.start()
    }
}
