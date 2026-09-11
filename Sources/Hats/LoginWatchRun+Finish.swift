import Foundation

extension LoginWatchRun {
    func finish() {
        guard windowClosedAt == nil else {
            duty.standDown(generation)
            releaseThePoll()
            return
        }
        releaseThePoll()
        closeTheLoginWindow { [self] outcome, stillRunning in
            duty.standDown(generation)
            guard duty.isTheCurrent(generation) else {
                Journal.log("login.closeAnsweredForAnOlderWatch", ["expecting": expecting ?? "-"])
                return
            }
            let gone = LoginWatchDuty.isTheScriptConfirmedGone(stillRunning)
            if gone { world.removeScript() }
            Journal.log("login.timedOut", [
                "expecting": expecting ?? "-",
                "closeAnswered": String(outcome != .couldNotAsk),
                "scriptStillRunning": stillRunning.map(String.init) ?? "unknown",
                "scriptRemoved": String(gone),
            ])
        }
    }

    private func releaseThePoll() {
        duty.stopPolling(generation)
        guard !observedTheLogin else { return }
        Journal.log("login.notObserved", [
            "expecting": expecting ?? "-",
            "reason": windowClosedAt != nil
                ? "the login window closed and nothing arrived"
                : "the watch ran out of time",
            "lastTrouble": lastTrouble() ?? "none",
        ])
        _ = syncWithWorld(false, nil)
    }
}
