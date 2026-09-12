import AppKit

extension HatDialogs {
    static func addHat() -> NewHat? {
        let state = HatFormState()
        let choices = BrowserChoice.available()
        state.browser = choices.first
        let prompt = HatPrompt(
            title: "Add a hat",
            text: "The sign-in page opens in the browser you pick. A browser signs you back into "
                + "whichever account it remembers, so two hats need two browser identities.",
            buttons: ["Add and log in", "Cancel"]
        )
        let chosen = PromptWindow.show(buttons: prompt.buttons.count) { choose in
            HatFormView(
                prompt: prompt,
                fields: [.name, .email, .browser],
                namePlaceholder: "name — Work, Personal, Team",
                choices: choices,
                chromeNames: ChromeProfiles.names(),
                state: state,
                choose: choose
            )
        }
        guard chosen == 0, let browser = state.browser else { return nil }

        return NewHat(
            name: Account.storableName(state.name),
            email: state.email.trimmingCharacters(in: .whitespaces),
            browser: browser
        )
    }

    static func rename(_ hat: Account) -> String?? {
        let state = HatFormState()
        state.name = hat.name ?? ""
        let prompt = HatPrompt(
            title: "Rename \(hat.title)",
            text: "The role is what you read in the list; the address stays underneath.",
            buttons: ["Save", "Cancel"]
        )
        let chosen = PromptWindow.show(buttons: prompt.buttons.count) { choose in
            HatFormView(
                prompt: prompt,
                fields: [.name],
                namePlaceholder: hat.email,
                choices: [],
                chromeNames: [:],
                state: state,
                choose: choose
            )
        }
        guard chosen == 0 else { return nil }

        return .some(Account.storableName(state.name))
    }

    static func browser(for hat: Account) -> BrowserChoice? {
        let state = HatFormState()
        let choices = BrowserChoice.available()
        state.browser = choices.first { $0 == hat.browser } ?? choices.first
        let prompt = HatPrompt(
            title: "Browser for \(hat.title)",
            text: "Where this hat's logins open. A browser signs you back into whichever "
                + "account it remembers, so each hat needs its own.",
            buttons: ["Save", "Cancel"]
        )
        let chosen = PromptWindow.show(buttons: prompt.buttons.count) { choose in
            HatFormView(
                prompt: prompt,
                fields: [.browser],
                namePlaceholder: "",
                choices: choices,
                chromeNames: ChromeProfiles.names(),
                state: state,
                choose: choose
            )
        }
        guard chosen == 0 else { return nil }

        return state.browser
    }
}
