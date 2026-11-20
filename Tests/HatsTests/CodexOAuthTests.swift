import XCTest
@testable import Hats

final class CodexOAuthTests: XCTestCase {
    func testTheChallengeIsTheSHA256OfTheVerifierInBase64URL() {
        XCTAssertEqual(CodexOAuth.challenge(for: "verifier-for-the-test_0123456789"),
                       "67faEYWtsCE-c5ynE05V8pVMLA_CLGj5nZCEFWZ1F2g",
                       "the same value Python's hashlib gives, the way the probe that signed in three times did")
    }

    func testTheVerifierIsSixtyFourBytesAndTheStateThirtyTwo() {
        let secrets = CodexOAuth.secrets(random: { Data(repeating: 7, count: $0) })

        XCTAssertEqual(secrets.verifier.count, 86)
        XCTAssertEqual(secrets.state.count, 43)
        XCTAssertEqual(CodexJWT.base64URLEncoded(Data(0..<64)),
                       "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-Pw")
    }

    func testTheAuthorizeAddressMatchesTheMeasuredProbeByteForByte() {
        let secrets = CodexOAuth.Secrets(verifier: "v", challenge: "CHALLENGE-x_y", state: "STATE-a_b")

        let url = CodexOAuth.authorizeURL(redirectURI: CodexOAuth.redirectURI(port: 1457), secrets: secrets)

        XCTAssertEqual(url?.absoluteString,
                       "https://auth.openai.com/oauth/authorize?response_type=code"
                           + "&client_id=app_EMoamEEZ73f0CkXaXp7hrann"
                           + "&redirect_uri=http%3A%2F%2F127.0.0.1%3A1457%2Fauth%2Fcallback"
                           + "&code_challenge=CHALLENGE-x_y&code_challenge_method=S256&state=STATE-a_b"
                           + "&scope=openid+profile+email+offline_access+api.connectors.read+api.connectors.invoke"
                           + "&id_token_add_organizations=true&codex_cli_simplified_flow=true&originator=codex_cli_rs")
    }

    func testOnlyTheTwoPortsTheServerAcceptsAreTried() {
        XCTAssertEqual(CodexOAuth.ports, [1455, 1457])
        XCTAssertEqual(CodexOAuth.redirectURI(port: 1455), "http://127.0.0.1:1455/auth/callback")
    }

    func testTheCodeIsExchangedWithAFormLikeCodexSends() throws {
        let request = CodexOAuth.exchangeRequest(
            code: "c o/d+e",
            redirectURI: "http://127.0.0.1:1455/auth/callback",
            verifier: "v-1"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/oauth/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8),
                       "grant_type=authorization_code&client_id=app_EMoamEEZ73f0CkXaXp7hrann&code=c+o%2Fd%2Be"
                           + "&redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback&code_verifier=v-1")
    }

    func testTheExchangeNeedsAllThreeTokens() {
        let full = Data(#"{"id_token":"i","access_token":"a","refresh_token":"r"}"#.utf8)
        let missing = Data(#"{"id_token":"i","access_token":"a"}"#.utf8)

        XCTAssertEqual(CodexOAuth.exchangeOutcome(status: 200, body: full),
                       .tokens(idToken: "i", accessToken: "a", refreshToken: "r"))
        XCTAssertEqual(CodexOAuth.exchangeOutcome(status: 200, body: missing),
                       .failed("the sign-in answer carried no tokens"))
        XCTAssertEqual(CodexOAuth.exchangeOutcome(status: 400, body: full), .failed("the sign-in server answered 400"))
        XCTAssertEqual(CodexOAuth.exchangeOutcome(status: 0, body: nil),
                       .failed("the sign-in server could not be reached"))
    }

    func testACallbackWithAnotherStateIsRefusedAndTheWaitGoesOn() {
        XCTAssertEqual(CodexCallback.judge(target: "/auth/callback?code=c&state=other", state: "mine"), .stateMismatch)
        XCTAssertEqual(CodexCallback.judge(target: "/auth/callback?code=c", state: "mine"), .stateMismatch)
    }

    func testTheCallbackTakesTheCodeAndTheLifeSciencesTail() {
        XCTAssertEqual(CodexCallback.judge(target: "/auth/callback?code=c-1&state=mine", state: "mine"), .code("c-1"))
        XCTAssertEqual(
            CodexCallback.judge(target: "/auth/callback?code=c-2&state=mine.onboarding_entrypoint%3Dlife_sciences",
                                state: "mine"),
            .code("c-2")
        )
    }

    func testARefusalOfThePageEndsTheSignIn() {
        XCTAssertEqual(
            CodexCallback.judge(
                target: "/auth/callback?state=s&error=access_denied&error_description=missing_codex_entitlement",
                state: "s"
            ),
            .refused("Codex is not enabled for this workspace.")
        )
        XCTAssertEqual(CodexCallback.judge(target: "/auth/callback?state=s&error=server_error", state: "s"),
                       .refused("The sign-in page refused: server_error."))
        XCTAssertEqual(CodexCallback.judge(target: "/auth/callback?state=s", state: "s"),
                       .refused("The sign-in page sent no authorization code."))
    }

    func testOtherPathsAreNotTheCallback() {
        XCTAssertEqual(CodexCallback.judge(target: "/success", state: "s"), .successPage)
        XCTAssertEqual(CodexCallback.judge(target: "/cancel", state: "s"), .notFound,
                       "a /cancel from another codex login does not end a sign-in of Hats")
        XCTAssertEqual(CodexCallback.judge(target: "/favicon.ico", state: "s"), .notFound)
    }
}
