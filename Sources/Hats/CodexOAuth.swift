import CryptoKit
import Foundation

enum CodexOAuth {
    static let issuer = "https://auth.openai.com"
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let ports = [1455, 1457]
    static let scope = "openid profile email offline_access api.connectors.read api.connectors.invoke"
    static let originator = "codex_cli_rs"
    static let lifeSciencesSuffix = ".onboarding_entrypoint=life_sciences"
    static let waitLimit: TimeInterval = 15 * 60
    static let budget: TimeInterval = 30

    static var tokenEndpoint: URL { URL(string: issuer + "/oauth/token") ?? URL(fileURLWithPath: "/") }

    struct Secrets: Equatable {
        let verifier: String
        let challenge: String
        let state: String
    }

    static func secrets(random: (Int) -> Data) -> Secrets {
        let verifier = CodexJWT.base64URLEncoded(random(64))

        return Secrets(
            verifier: verifier,
            challenge: challenge(for: verifier),
            state: CodexJWT.base64URLEncoded(random(32))
        )
    }

    static func challenge(for verifier: String) -> String {
        CodexJWT.base64URLEncoded(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func systemRandom(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()

        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    static func redirectURI(port: Int) -> String { "http://127.0.0.1:\(port)/auth/callback" }

    static func authorizeURL(redirectURI: String, secrets: Secrets) -> URL? {
        let pairs = [
            ("response_type", "code"),
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("code_challenge", secrets.challenge),
            ("code_challenge_method", "S256"),
            ("state", secrets.state),
            ("scope", scope),
            ("id_token_add_organizations", "true"),
            ("codex_cli_simplified_flow", "true"),
            ("originator", originator),
        ]

        return URL(string: issuer + "/oauth/authorize?" + formEncoded(pairs))
    }

    static func formEncoded(_ pairs: [(String, String)]) -> String {
        pairs.map { formComponent($0.0) + "=" + formComponent($0.1) }.joined(separator: "&")
    }

    static func formComponent(_ text: String) -> String {
        var out = ""
        for byte in text.utf8 {
            let scalar = Unicode.Scalar(byte)
            if byte < 0x80, CharacterSet.alphanumerics.contains(scalar) || "*-._".unicodeScalars.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else if byte == 0x20 {
                out += "+"
            } else {
                out += String(format: "%%%02X", byte)
            }
        }

        return out
    }

    static func exchangeRequest(code: String, redirectURI: String, verifier: String) -> URLRequest {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = budget
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded([
            ("grant_type", "authorization_code"),
            ("client_id", clientID),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("code_verifier", verifier),
        ]).utf8)

        return request
    }

    enum Exchange: Equatable {
        case tokens(idToken: String, accessToken: String, refreshToken: String)
        case failed(String)
    }

    static func exchangeOutcome(status: Int, body: Data?) -> Exchange {
        guard status != 0 else { return .failed("the sign-in server could not be reached") }
        guard (200..<300).contains(status) else { return .failed("the sign-in server answered \(status)") }
        guard let body,
              let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let id = payload["id_token"] as? String, !id.isEmpty,
              let access = payload["access_token"] as? String, !access.isEmpty,
              let refresh = payload["refresh_token"] as? String, !refresh.isEmpty
        else { return .failed("the sign-in answer carried no tokens") }

        return .tokens(idToken: id, accessToken: access, refreshToken: refresh)
    }
}
