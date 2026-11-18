import Foundation

struct CodexHTTPAnswer: Equatable {
    let status: Int
    let headers: [String: String]
    let body: Data

    static func page(_ status: Int, _ text: String) -> CodexHTTPAnswer {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let html = "<!doctype html><html><head><meta charset='utf-8'><title>Hats</title></head>"
            + "<body style='font-family:-apple-system,sans-serif;margin:48px'><p>\(escaped)</p></body></html>"

        return CodexHTTPAnswer(
            status: status,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: Data(html.utf8)
        )
    }

    static func plain(_ status: Int, _ text: String) -> CodexHTTPAnswer {
        CodexHTTPAnswer(status: status, headers: ["Content-Type": "text/plain; charset=utf-8"], body: Data(text.utf8))
    }

    static let toTheSuccessPage = CodexHTTPAnswer(status: 302, headers: ["Location": "/success"], body: Data())
}

enum CodexCallback: Equatable {
    case stateMismatch
    case refused(String)
    case code(String)
    case successPage
    case notFound

    static let path = "/auth/callback"

    static func judge(target: String, state expected: String) -> CodexCallback {
        guard let parts = URLComponents(string: "http://127.0.0.1" + target) else { return .notFound }
        if parts.path == "/success" { return .successPage }
        guard parts.path == path else { return .notFound }
        var query: [String: String] = [:]
        for item in parts.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        var state = query["state"]
        if let given = state, given.hasSuffix(CodexOAuth.lifeSciencesSuffix),
           String(given.dropLast(CodexOAuth.lifeSciencesSuffix.count)) == expected {
            state = expected
        }
        guard state == expected else { return .stateMismatch }
        if let error = query["error"] {
            return .refused(refusal(error: error, description: query["error_description"]))
        }
        guard let code = query["code"], !code.isEmpty else {
            return .refused("The sign-in page sent no authorization code.")
        }

        return .code(code)
    }

    static func refusal(error: String, description: String?) -> String {
        let said = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if error == "access_denied", said.lowercased().contains("missing_codex_entitlement") {
            return "Codex is not enabled for this workspace."
        }

        return said.isEmpty ? "The sign-in page refused: \(error)." : "The sign-in page refused: \(said)"
    }
}
