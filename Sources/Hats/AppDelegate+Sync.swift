import AppKit

extension AppDelegate {
    @discardableResult
    func syncWithWorld(reportingErrors: Bool = true, claiming claim: CredentialClaim? = nil) -> String? {
        let claim = claim ?? .forSync(duty: login.duty())
        let identity = store.liveIdentity()
        liveIdentity = identity
        var reconciled: String?
        do {
            let outcome = try store.reconcileWithLiveLogin(observing: identity, claiming: claim)
            store.pruneOrphanedCredentials()
            if case .reconciled(let account, _) = outcome { reconciled = account }
            noteSyncTrouble(outcome.unsettledReason, shownToTheUser: false)
        } catch {
            noteSyncTrouble(error.localizedDescription, shownToTheUser: reportingErrors)
            if reportingErrors { HatDialogs.present(error, title: "Could not read the accounts") }
        }
        redraw()
        return reconciled
    }

    private func noteSyncTrouble(_ reason: String?, shownToTheUser: Bool) {
        guard let reason else {
            lastSyncFailure = nil
            return
        }
        guard reason != lastSyncFailure else { return }
        Journal.log("sync.unsettled", ["reason": reason, "shownToTheUser": String(shownToTheUser)])
        lastSyncFailure = reason
    }
}
