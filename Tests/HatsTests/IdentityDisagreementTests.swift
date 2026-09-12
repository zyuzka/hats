import XCTest
@testable import Hats

final class IdentityReadingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func stateFile(_ email: String) -> CLIIdentity {
        CLIIdentity(oauthAccount: ["emailAddress": .string(email)], userID: "u")
    }

    func testAnAgreeingStateFileIsTheIdentityAndNothingToReport() {
        let reading = IdentityReading.of(cliSays: "a@b.com", stateFile: stateFile("A@B.com"), at: now)

        XCTAssertEqual(reading.identity?.email, "A@B.com", "the address is compared case-blind")
        XCTAssertNil(reading.disagreement)
    }

    func testADisagreeingStateFileIsReportedWithBothAddresses() throws {
        let reading = IdentityReading.of(cliSays: "a@b.com", stateFile: stateFile("c@d.com"), at: now)
        let disagreement = try XCTUnwrap(reading.disagreement)

        XCTAssertNil(reading.identity, "storing it would write the wrong account into the CLI's "
            + "own state file on the next switch")
        XCTAssertEqual(disagreement.cliSays, "a@b.com")
        XCTAssertEqual(disagreement.stateFileSays, "c@d.com")
        XCTAssertEqual(disagreement.seenAt, now)
    }

    func testAStateFileThatSaysNothingIsItsOwnCase() throws {
        let reading = IdentityReading.of(cliSays: "a@b.com", stateFile: nil, at: now)
        let disagreement = try XCTUnwrap(reading.disagreement)

        XCTAssertNil(reading.identity)
        XCTAssertNil(disagreement.stateFileSays,
                     "no account in the file and a different account in it are different troubles, "
                         + "and a person can only act on the one they are told about")
    }
}

final class IdentityDisagreementCopyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func hat(disagreement: IdentityDisagreement?) -> Account {
        var hat = Account(id: "a", email: "a@b.com", browser: nil)
        hat.hasStoredCredentials = true
        hat.identityDisagreement = disagreement

        return hat
    }

    func testAKnownDisagreementIsNotTheSameStatusAsAMissingIdentity() {
        XCTAssertEqual(HatsCopy.blocker(for: hat(disagreement: nil), now: now), "needs one more login")
        XCTAssertEqual(
            HatsCopy.blocker(for: hat(disagreement: .init(cliSays: "a@b.com",
                                                          stateFileSays: "c@d.com",
                                                          seenAt: now)), now: now),
            "accounts disagree",
            "'needs one more login' tells a person to do the one thing that will not help, because "
                + "the next login writes the same two disagreeing places again")
    }

    func testTheExplanationNamesBothSidesAndTheConsequence() {
        XCTAssertEqual(
            HatsCopy.identityDisagreement(.init(cliSays: "a@b.com", stateFileSays: "c@d.com", seenAt: now)),
            "Claude Code reports a@b.com while its state file names c@d.com. Until they agree this "
                + "hat has no account to put back, so switching to it would refuse."
        )
        XCTAssertEqual(
            HatsCopy.identityDisagreement(.init(cliSays: "a@b.com", stateFileSays: nil, seenAt: now)),
            "Claude Code reports a@b.com while its state file names no account at all. Until that "
                + "changes this hat has no account to put back, so switching to it would refuse."
        )
    }
}
