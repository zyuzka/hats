import XCTest
@testable import Hats

final class CodexServiceLoginRereadMatchTests: XCTestCase {
    private let harness = CodexRereadHarness()

    override func setUpWithError() throws {
        try super.setUpWithError()
        try harness.makeTheSocketFile()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: harness.folder)
        super.tearDown()
    }

    private func rereadForWork(answering account: CodexServiceAccount) -> [String] {
        harness.link.answer = .success(account)
        harness.makeReread().rereadNow(for: "hat-work-123", expecting: CodexRereadHarness.expectingWork)

        return harness.lines.map(\.0)
    }

    func testAServiceStillOnAnotherAccountIsLoggedAsSuch() {
        let lines = rereadForWork(answering: CodexServiceAccount(
            email: "personal@example.com",
            owner: CodexFixture.personal.owner
        ))

        XCTAssertEqual(lines, ["codexService.loginReread.otherAccount"])
        XCTAssertEqual(
            harness.lines.first?.1,
            ["hat": "hat-work", "account": "personal@example.com", "expected": "work@example.com"]
        )
    }

    func testTheSameEmailInAnotherWorkspaceIsAnotherAccount() {
        let other = CodexOwner(userID: CodexFixture.work.owner.userID, accountID: "acct-other-workspace")

        let lines = rereadForWork(answering: CodexServiceAccount(email: "work@example.com", owner: other))

        XCTAssertEqual(lines, ["codexService.loginReread.otherAccount"])
    }

    func testAServiceThatNamesNoAccountIsNotLoggedAsDone() {
        let lines = rereadForWork(answering: CodexServiceAccount(email: nil, owner: nil))

        XCTAssertEqual(lines, ["codexService.loginReread.otherAccount"])
        XCTAssertEqual(harness.lines.first?.1, ["hat": "hat-work", "account": "-", "expected": "work@example.com"])
    }

    func testWithoutAnOwnerTheEmailIsMatchedWithoutRegardToLetterCase() {
        let lines = rereadForWork(answering: CodexServiceAccount(email: "Work@Example.com", owner: nil))

        XCTAssertEqual(lines, ["codexService.loginReread.done"])
    }

    func testALoginThatNamesNoEmailOrOwnerTakesWhateverTheServiceHolds() {
        harness.link.answer = .success(CodexRereadHarness.work)

        harness.makeReread().rereadNow(for: "hat-work-123", expecting: (nil, nil))

        XCTAssertEqual(harness.lines.map(\.0), ["codexService.loginReread.done"])
    }
}
