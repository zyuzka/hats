import Foundation

extension LoginWatchRun {
    func finish() {
        guard windowClosedAt == nil else {
            duty.standDown(generation)
            releaseThePoll()
            return
        }
        releaseThePoll()
        duty.standDown(generation)
        closeTheLoginWindow()
        Journal.log("login.timedOut", ["expecting": expecting ?? "-"])
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
