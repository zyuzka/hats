import AppKit

struct NewHat {
    let name: String?
    let email: String
    let browser: BrowserChoice
}

enum HatDialogs {
    static func hasConfirmedRemoval(of hat: Account) -> Bool {
        PromptWindow.ask(HatPrompt(
            title: "Remove \(hat.title)?",
            text: "Its stored login is deleted from this Mac. You can add the hat again later.",
            buttons: ["Remove", "Cancel"]
        )) == 0
    }

    static func hasConfirmedLoginAnyway(for hat: Account) -> Bool {
        var text = "Putting it on works without logging in. A new login replaces the token that already works."
        if let validity = HatsCopy.loginValidity(for: hat) { text = "Its stored login is \(validity). " + text }

        return PromptWindow.ask(HatPrompt(
            title: "\(hat.title) does not need a login",
            text: text,
            buttons: ["Log in anyway", "Cancel"]
        )) == 0
    }

    static func hasConfirmedQuit(cost: String) -> Bool {
        PromptWindow.ask(HatPrompt(
            title: "Quit Hats?",
            text: cost,
            buttons: ["Quit", "Cancel"]
        )) == 0
    }

    static func hasConfirmedStoppingTheGateway(cost: String) -> Bool {
        PromptWindow.ask(HatPrompt(
            title: "Turn the gateway off?",
            text: cost,
            buttons: ["Turn it off", "Cancel"]
        )) == 0
    }

    static func hasConfirmedRestartingTheGateway(cost: String) -> Bool {
        PromptWindow.ask(HatPrompt(
            title: "Restart the gateway?",
            text: cost,
            buttons: ["Restart it", "Cancel"]
        )) == 0
    }

    static func askAboutTheSignInInFlight(_ text: String) -> SignInInFlightChoice {
        SignInInFlightChoice.of(PromptWindow.ask(HatPrompt(
            title: "A sign-in is already running",
            text: text,
            buttons: ["Show it", "Cancel that sign-in", "Cancel"]
        )))
    }

    static func inform(_ title: String, _ text: String) {
        _ = PromptWindow.ask(HatPrompt(title: title, text: text, buttons: ["OK"]))
    }

    static func present(_ error: Error, title: String = "Could not put that hat on") {
        _ = PromptWindow.ask(HatPrompt(
            title: title,
            text: error.localizedDescription,
            buttons: ["OK"]
        ))
    }

}
