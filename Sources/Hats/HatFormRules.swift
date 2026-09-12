import Foundation

enum HatFormRules {
    static func canAdd(email: String, browser: BrowserChoice?) -> Bool {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let browser, browser.overridesBrowser else { return false }

        return true
    }
}
