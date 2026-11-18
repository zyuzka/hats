import AppKit

extension AppDelegate {
    func addCodexHat(_ wanted: NewHat) {
        let new = CodexNewHat(name: wanted.name, email: wanted.email, browser: wanted.browser)
        if let live = Self.liveLoginToAdopt(in: .real, as: wanted.email) {
            do {
                let hat = try store.addCodexHat(new, login: live, isLive: true)
                codex.desk.noteWorn(hat.id)
                redraw()
                HatDialogs.inform(HatsCopy.codexAlreadySignedInTitle, HatsCopy.codexAlreadySignedIn(hat.title))
            } catch {
                redraw()
                HatDialogs.present(error, title: "Could not add that hat")
            }
            return
        }
        signInToCodex(as: wanted.email, hat: wanted.name ?? wanted.email, browser: wanted.browser) { [weak self] data in
            guard let self else { return }
            _ = try self.store.addCodexHat(new, login: data, isLive: false)
        }
    }

    static func liveLoginToAdopt(in home: CodexHome, as email: String, at now: Date = Date()) -> Data? {
        guard (try? home.requireFileStore()) != nil,
              let live = try? home.readLiveChecked(),
              isAlreadySignedIn(live, as: email, at: now) else { return nil }

        return live
    }

    static func isAlreadySignedIn(_ live: Data, as email: String, at now: Date = Date()) -> Bool {
        guard let auth = CodexAuth(data: live), auth.problem == nil,
              let expiry = auth.accessExpiry, expiry > now else { return false }
        guard let said = auth.identity?.email else { return false }

        return Account.sameAddress(said, email)
    }

    func reloginCodex(_ id: String) {
        guard let hat = store.codexHats.first(where: { $0.id == id }) else { return }
        guard let browser = hat.browser else {
            return HatDialogs.present(CodexError.noBrowser(hat.title), title: "Could not start the Codex sign-in")
        }
        signInToCodex(as: hat.email, hat: hat.title, browser: browser) { [weak self] data in
            guard let self else { return }
            let ticket = try self.store.checkCodexRelogin(id, login: data)
            let isWorn = self.store.codexActiveID == id
            let tickets = self.store.codexTickets
            self.codex.desk.relogin(ticket, with: data, isWorn: isWorn, among: tickets) { stored, result in
                self.store.noteCodexRelogin(id, login: data, stored: stored, outcome: try? result.get())
                if case .failure(let error) = result {
                    HatDialogs.present(error, title: "Could not finish the Codex login")
                }
                self.redraw()
            }
        }
    }

    func signInToCodex(
        as email: String,
        hat: String,
        browser: BrowserChoice,
        store save: @escaping (Data) throws -> Void
    ) {
        guard !codex.signIn.isRunning else {
            codex.signIn.showTheWindow()
            return HatDialogs.inform(HatsCopy.codexSignInBusyTitle, HatsCopy.codexSignInBusy)
        }
        let model = CodexSignInModel(
            title: HatsCopy.codexSigningIn(email),
            text: HatsCopy.codexSignInText(browser.label(chromeNames: ChromeProfiles.names()))
        )
        do {
            try codex.signIn.begin(model, hat: hat, browser: browser) { [weak self] ending in
                switch ending {
                case .signedIn(let data):
                    do {
                        try save(data)
                    } catch {
                        HatDialogs.present(error, title: "Could not store that Codex login")
                    }
                case .refused(let why):
                    HatDialogs.inform(HatsCopy.codexSignInFailedTitle, why)
                case .timedOut:
                    HatDialogs.inform(HatsCopy.codexSignInFailedTitle, HatsCopy.codexSignInTimedOut)
                case .cancelled:
                    break
                }
                self?.redraw()
            }
        } catch {
            HatDialogs.present(error, title: "Could not start the Codex sign-in")
        }
    }
}
