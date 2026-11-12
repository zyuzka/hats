import AppKit

extension AppDelegate {
    func installSessionHandoff() {
        handoff.install()
    }

    func removeSessionHandoff() {
        handoff.remove()
    }
}
