import XCTest
@testable import Hats

final class CodexSlotListingTests: XCTestCase {
    private let dump = """
    keychain: "/Users/me/Library/Keychains/login.keychain-db"
    attributes:
        "acct"<blob>="me"
        "svce"<blob>="Hats parked A"
    keychain: "/Users/me/Library/Keychains/login.keychain-db"
    attributes:
        "acct"<blob>="me"
        "svce"<blob>="Hats Codex parked C"
    keychain: "/Users/me/Library/Keychains/login.keychain-db"
    attributes:
        "acct"<blob>="me"
        "svce"<blob>="TMK acc-switch parked L"
    """

    func testTheClaudeListingSeesNoCodexSlotAndTheCodexListingOnlyCodexSlots() {
        XCTAssertEqual(Set(Keychain.parsedParkedIDs(dump: dump, account: "me")), ["A", "L"],
                       "the prune of Claude slots must not see C, or it would delete a Codex login")
        XCTAssertEqual(Keychain.parsedParkedIDs(dump: dump, account: "me", prefixes: [Slot.codexParked("")]), ["C"])
    }
}
