import AppKit

struct NewHat {
    let name: String?
    let email: String
    let browser: BrowserChoice
}

enum HatDialogs {
    static func run(_ alert: NSAlert, focus: NSView? = nil) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        if let focus { alert.window.initialFirstResponder = focus }
        alert.window.makeKeyAndOrderFront(nil)
        return alert.runModal()
    }

    static func addHat() -> NewHat? {
        let alert = NSAlert()
        alert.messageText = "Add a hat"
        alert.informativeText = "The sign-in page opens in the browser you pick. A browser signs you back into "
            + "whichever account it remembers, so two hats need two browser identities."
        let name = field(y: 56, placeholder: "name — Work, Personal, Team")
        let email = field(y: 28, placeholder: "email address")
        let (browser, choices) = browserPicker()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        [name, email, browser].forEach(container.addSubview)
        alert.accessoryView = container
        alert.addButton(withTitle: "Add and log in")
        alert.addButton(withTitle: "Cancel")
        guard run(alert, focus: name) == .alertFirstButtonReturn else { return nil }
        let address = email.stringValue.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty, let chosen = chosen(in: browser, from: choices) else { return nil }
        return NewHat(
            name: Account.storableName(name.stringValue),
            email: address,
            browser: chosen
        )
    }

    private static func browserPicker(selecting current: BrowserChoice? = nil) -> (NSPopUpButton, [BrowserChoice]) {
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        let choices = BrowserChoice.available()
        let chromeNames = ChromeProfiles.names()
        for (index, choice) in choices.enumerated() {
            let item = NSMenuItem(title: choice.label(chromeNames: chromeNames), action: nil, keyEquivalent: "")
            item.representedObject = index
            picker.menu?.addItem(item)
        }
        if let current, let index = choices.firstIndex(of: current) {
            picker.selectItem(at: index)
        }
        return (picker, choices)
    }

    private static func chosen(in picker: NSPopUpButton, from choices: [BrowserChoice]) -> BrowserChoice? {
        guard let index = picker.selectedItem?.representedObject as? Int,
              choices.indices.contains(index) else { return nil }
        return choices[index]
    }

    static func rename(_ hat: Account) -> String?? {
        let alert = NSAlert()
        alert.messageText = "Rename \(hat.title)"
        alert.informativeText = "The role is what you read in the list; the address stays underneath."
        let name = field(y: 0, placeholder: hat.email)
        name.stringValue = hat.name ?? ""
        alert.accessoryView = name
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard run(alert, focus: name) == .alertFirstButtonReturn else { return nil }
        return .some(Account.storableName(name.stringValue))
    }

    static func browser(for hat: Account) -> BrowserChoice? {
        let alert = NSAlert()
        alert.messageText = "Browser for \(hat.title)"
        alert.informativeText = "Where this hat's logins open. A browser signs you back into whichever "
            + "account it remembers, so each hat needs its own."
        let (picker, choices) = browserPicker(selecting: hat.browser)
        alert.accessoryView = picker
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard run(alert, focus: picker) == .alertFirstButtonReturn else { return nil }
        return chosen(in: picker, from: choices)
    }

    static func hasConfirmedRemoval(of hat: Account) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Remove \(hat.title)?"
        alert.informativeText = "Its stored login is deleted from this Mac. You can add the hat again later."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        return run(alert) == .alertFirstButtonReturn
    }

    static func hasConfirmedLoginAnyway(for hat: Account) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(hat.title) does not need a login"
        var text = "Putting it on works without logging in. A new login replaces the token that already works."
        if let validity = HatsCopy.loginValidity(for: hat) { text = "Its stored login is \(validity). " + text }
        alert.informativeText = text
        alert.addButton(withTitle: "Log in anyway")
        alert.addButton(withTitle: "Cancel")
        return run(alert) == .alertFirstButtonReturn
    }

    static func hasConfirmedQuit(cost: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Quit Hats?"
        alert.informativeText = cost
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return run(alert) == .alertFirstButtonReturn
    }

    static func hasConfirmedStoppingTheGateway(cost: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Turn the gateway off?"
        alert.informativeText = cost
        alert.addButton(withTitle: "Turn it off")
        alert.addButton(withTitle: "Cancel")
        return run(alert) == .alertFirstButtonReturn
    }

    static func hasConfirmedRestartingTheGateway(cost: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Restart the gateway?"
        alert.informativeText = cost
        alert.addButton(withTitle: "Restart it")
        alert.addButton(withTitle: "Cancel")
        return run(alert) == .alertFirstButtonReturn
    }

    static func askAboutTheSignInInFlight(_ text: String) -> SignInInFlightChoice {
        let alert = NSAlert()
        alert.messageText = "A sign-in is already running"
        alert.informativeText = text
        alert.addButton(withTitle: "Show it")
        alert.addButton(withTitle: "Cancel that sign-in")
        alert.addButton(withTitle: "Cancel")
        return SignInInFlightChoice.of(run(alert))
    }

    static func inform(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        _ = run(alert)
    }

    static func present(_ error: Error, title: String = "Could not put that hat on") {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        _ = run(alert)
    }

    private static func field(y: CGFloat, placeholder: String) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 0, y: y, width: 300, height: 24))
        field.placeholderString = placeholder
        return field
    }
}
