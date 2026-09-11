import XCTest
@testable import Hats

final class HatTests: XCTestCase {
    func testTheTitleIsTheNameWhenThereIsOneAndTheAddressOtherwise() {
        var hat = Account(id: "a", email: "filip@company.com", browser: nil)
        XCTAssertEqual(hat.title, "filip@company.com", "an unnamed hat is still readable")
        hat.name = "Work"
        XCTAssertEqual(hat.title, "Work", "the role is what you read; the address is the detail")
        hat.name = "   "
        XCTAssertEqual(hat.title, "filip@company.com", "a blank name is no name")
    }

    func testAHatWithoutAToolBelongsToClaudeCode() {
        let hat = Account(id: "a", email: "x@y.z", browser: nil)
        XCTAssertNil(hat.tool, "nothing was written, so nothing is stored")
        XCTAssertEqual(hat.wornTool, .claudeCode)
    }

    func testAnAccountWrittenBeforeHatsStillDecodes() throws {
        let legacy = """
        {"id":"a","email":"filip@company.com","hasStoredCredentials":true}
        """
        let hat = try JSONDecoder().decode(Account.self, from: Data(legacy.utf8))
        XCTAssertNil(hat.name)
        XCTAssertNil(hat.tool)
        XCTAssertEqual(hat.title, "filip@company.com")
        XCTAssertEqual(hat.wornTool, .claudeCode)
    }

    func testSwitchabilityNeedsCredentialsAnIdentityAndAnUnexpiredLogin() {
        var hat = Account(id: "a", email: "x@y.z", browser: nil)
        XCTAssertFalse(hat.isSwitchable, "no login stored")
        hat.hasStoredCredentials = true
        XCTAssertFalse(hat.isSwitchable, "one more login is needed for the identity")
        hat.identity = CLIIdentity(oauthAccount: ["emailAddress": .string("x@y.z")], userID: nil)
        XCTAssertTrue(hat.isSwitchable)
        hat.refreshExpiresAt = Date().addingTimeInterval(-1)
        XCTAssertFalse(hat.isSwitchable, "an expired login cannot be put on")
        XCTAssertEqual(hat.blocker(), .loginExpired, "switchability and the blocker are one judgement, read two ways")
    }
}
