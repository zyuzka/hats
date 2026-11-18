import XCTest
@testable import Hats

final class CodexCopyTests: XCTestCase {
    private let now = CodexFixture.now

    private func codexHat(accessIn seconds: TimeInterval?) -> Account {
        var hat = Account(id: "c", email: "work@example.com", name: "work")
        hat.tool = .codex
        hat.hasStoredCredentials = true
        hat.codexOwner = CodexFixture.work.owner
        hat.accessExpiresAt = seconds.map { now.addingTimeInterval($0) }

        return hat
    }

    func testTheManagePanelShowsTheAccessTokenOfACodexHatAndNeverUnknown() {
        XCTAssertEqual(HatsCopy.loginLine(for: codexHat(accessIn: 3 * 86400 + 2 * 3600), now: now),
                       "access token valid 3d 2h")
        XCTAssertNil(HatsCopy.loginLine(for: codexHat(accessIn: nil), now: now))
        XCTAssertEqual(HatRowState(hat: codexHat(accessIn: 7200), isWearing: false, usage: nil, usageTrouble: nil,
                                   now: now).loginValidity, "access token valid \(HatsCopy.humanise(7200))")
        XCTAssertNotEqual(HatRowState(hat: codexHat(accessIn: nil), isWearing: false, usage: nil, usageTrouble: nil,
                                      now: now).loginValidity, "expiry unknown")
    }

    func testTheWornCodexHatIsNotPromisedARenewalItDoesNotGet() {
        XCTAssertEqual(HatsCopy.loginLine(for: codexHat(accessIn: -60), isWorn: true, now: now), "access token expired")
        XCTAssertEqual(HatsCopy.loginLine(for: codexHat(accessIn: -60), isWorn: false, now: now),
                       "access token expired, renewed when parked")
    }

    func testACodexHatAsksToSignInAndItsTitleIsFoundInTheCodexList() {
        let row = HatRowState(hat: codexHat(accessIn: 60), isWearing: false, usage: nil, usageTrouble: nil, now: now)
        var snapshot = HatsSnapshot()
        snapshot.codexRows = [row]

        XCTAssertEqual(row.loginAction, "Sign in again…")
        XCTAssertEqual(snapshot.title(of: "c"), "work")
    }

    func testAClaudeHatKeepsItsOwnLines() {
        var claude = Account(id: "a", email: "a@b.co")
        claude.hasStoredCredentials = true

        XCTAssertEqual(HatsCopy.loginLine(for: claude, now: now), "expiry unknown")
        XCTAssertEqual(HatsCopy.loginAnywayText(for: claude, now: now), HatsCopy.getLoginAnywayText(for: claude, now: now))
        XCTAssertEqual(HatsCopy.loginAnywayTitle(for: claude), "a@b.co does not need a login")
        XCTAssertEqual(HatsCopy.loginAnywayButton(for: claude), "Log in anyway")
    }

    func testSigningACodexHatInAgainIsAskedInCodexWords() {
        let hat = codexHat(accessIn: 86400)
        let text = HatsCopy.loginAnywayText(for: hat, now: now)

        XCTAssertEqual(HatsCopy.loginAnywayTitle(for: hat), "work does not need a sign-in")
        XCTAssertEqual(HatsCopy.loginAnywayButton(for: hat), "Sign in anyway")
        XCTAssertTrue(text.hasPrefix("Its access token valid \(HatsCopy.humanise(86400)). "), text)
        XCTAssertTrue(text.contains("ChatGPT"))
        XCTAssertNotEqual(text, HatsCopy.getLoginAnywayText(for: hat, now: now))
    }
}
