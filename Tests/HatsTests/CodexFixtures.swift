import Foundation
@testable import Hats

enum CodexFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func jwt(_ payload: [String: Any]) -> String {
        let header = CodexJWT.base64URLEncoded(Data(#"{"alg":"none"}"#.utf8))
        let body = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()

        return header + "." + CodexJWT.base64URLEncoded(body) + ".c2lnbmF0dXJl"
    }

    static func idToken(user: String, account: String?, email: String?, plan: String = "plus") -> String {
        var auth: [String: Any] = ["chatgpt_user_id": user, "chatgpt_plan_type": plan]
        if let account { auth["chatgpt_account_id"] = account }
        var payload: [String: Any] = [CodexIdentity.authClaim: auth, "sub": "auth0|\(user)"]
        if let email { payload["email"] = email }

        return jwt(payload)
    }

    static func accessToken(expiresAt: Date?, tag: String) -> String {
        var payload: [String: Any] = ["tag": tag]
        if let expiresAt { payload["exp"] = Int(expiresAt.timeIntervalSince1970) }

        return jwt(payload)
    }

    struct Person {
        let user: String
        let account: String
        let email: String

        var owner: CodexOwner { CodexOwner(userID: user, accountID: account) }
    }

    static let work = Person(user: "user-work", account: "acct-work", email: "work@example.com")
    static let personal = Person(user: "user-personal", account: "acct-personal", email: "personal@example.com")

    static func login(
        _ person: Person,
        refresh: String,
        expiresAt: Date? = now.addingTimeInterval(5 * 24 * 3600),
        signedInAt: Date = now
    ) -> Data {
        let auth = CodexAuth.signedIn(
            idToken: idToken(user: person.user, account: person.account, email: person.email),
            accessToken: accessToken(expiresAt: expiresAt, tag: refresh),
            refreshToken: refresh,
            loginOwnerID: "owner-\(refresh)",
            at: signedInAt
        )

        return (try? auth.data()) ?? Data()
    }

    static func refreshToken(in data: Data?) -> String? { data.flatMap { CodexAuth(data: $0)?.refreshToken } }

    static func home() -> CodexHome {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hats-codex-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var home = CodexHome(url: url)
        home.lockWait = 0.3

        return home
    }

    static func ticket(_ id: String, _ person: Person) -> CodexTicket {
        CodexTicket(id: id, owner: person.owner, title: id, needsSignIn: false)
    }
}

final class FakeCodexServer {
    var answers: [(status: Int, body: Data?)] = []
    var sent: [URLRequest] = []
    var duringSend: () -> Void = {}

    var sentRefreshTokens: [String] {
        sent.compactMap { request in
            guard let body = request.httpBody,
                  let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            else { return nil }
            return json["refresh_token"] as? String
        }
    }

    func renewed(_ fields: [String: String]) {
        answers.append((200, try? JSONSerialization.data(withJSONObject: fields)))
    }

    func send(_ request: URLRequest) -> (status: Int, body: Data?) {
        sent.append(request)
        duringSend()
        guard !answers.isEmpty else { return (0, nil) }
        return answers.removeFirst()
    }

    func world(home: CodexHome, keychain: FakeKeychain, now: Date = CodexFixture.now) -> CodexWorld {
        CodexWorld(
            home: home,
            keychain: keychain.world(),
            send: { [unowned self] in self.send($0) },
            now: { now },
            run: { $0() },
            onMain: { $0() }
        )
    }
}
