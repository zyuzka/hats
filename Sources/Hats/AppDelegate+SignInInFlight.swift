import AppKit

extension AppDelegate {
    func whenNoSignInIsRunning(_ resume: @escaping () -> Void) {
        guard !login.canStartALogin() else { return resume() }
        switch HatDialogs.askAboutTheSignInInFlight(HatsCopy.signInInFlight) {
        case .showTheWindow:
            login.showTheSignInWindow()
        case .abandonIt:
            login.abandonTheSignIn(then: resume)
        case .leaveItAlone:
            break
        }
    }
}
