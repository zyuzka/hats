import XCTest
@testable import Hats

final class KeychainDumpTests: XCTestCase {
    fileprivate let mine = "local-user"

    fileprivate func item(account: String?, service: String?) -> String {
        var block = "keychain: \"/Users/local-user/Library/Keychains/login.keychain-db\"\n"
        block += "class: \"genp\"\nattributes:\n"
        block += "    0x00000007 <blob>=\"\(service ?? "none")\"\n"
        block += account.map { "    \"acct\"<blob>=\"\($0)\"\n" } ?? "    \"acct\"<blob>=<NULL>\n"
        block += service.map { "    \"svce\"<blob>=\"\($0)\"\n" } ?? ""
        return block
    }

    func testAParkedSlotOfThisAccountIsListed() {
        let dump = item(account: mine, service: Slot.parked("A-1"))
        XCTAssertEqual(Keychain.parsedParkedIDs(dump: dump, account: mine), ["A-1"])
    }

    func testAParkedSlotStoredUnderAnotherAccountIsNotThisStores() {
        let dump = item(account: "someone-else", service: Slot.parked("A-1"))
        XCTAssertEqual(Keychain.parsedParkedIDs(dump: dump, account: mine), [])
    }

    func testTheAccountOfOneItemDoesNotVouchForTheServiceOfTheNext() {
        let dump = item(account: mine, service: "com.apple.assistant")
            + item(account: "someone-else", service: Slot.parked("A-1"))
        XCTAssertEqual(Keychain.parsedParkedIDs(dump: dump, account: mine), [])
    }

    func testAnItemWithNoAccountIsSkipped() {
        let dump = item(account: nil, service: Slot.parked("A-1"))
        XCTAssertEqual(Keychain.parsedParkedIDs(dump: dump, account: mine), [])
    }

    func testTheLiveSlotIsNotAParkedOne() {
        let dump = item(account: mine, service: CLIState.credentialService(environment: [:]))
        XCTAssertEqual(Keychain.parsedParkedIDs(dump: dump, account: mine), [])
    }

    func testAServiceThatOnlyStartsLikeAParkedOneCarriesNoID() {
        let dump = item(account: mine, service: Slot.parked(""))
        XCTAssertEqual(Keychain.parsedParkedIDs(dump: dump, account: mine), [])
    }

    func testEveryParkedSlotOfThisAccountIsFoundAmongOtherApps() {
        let dump = item(account: "Chrome", service: "Chrome Safe Storage")
            + item(account: mine, service: Slot.parked("A-1"))
            + item(account: "Siri Global", service: "com.apple.assistant")
            + item(account: mine, service: Slot.parked("B-2"))
        XCTAssertEqual(Keychain.parsedParkedIDs(dump: dump, account: mine).sorted(),
                       ["A-1", "B-2"])
    }

    func testAServiceNameWithSpacesSurvivesTheRead() {
        let dump = item(account: mine, service: Slot.parked("D0582D9E-8274-44E3"))
        XCTAssertEqual(Keychain.parsedParkedIDs(dump: dump, account: mine),
                       ["D0582D9E-8274-44E3"])
    }

    func testAnEmptyDumpListsNothing() {
        XCTAssertEqual(Keychain.parsedParkedIDs(dump: "", account: mine), [])
    }

    func testAFailedDumpIsNotAnEmptyKeychain() {
        XCTAssertThrowsError(try Keychain.parkedAccountIDs(account: mine, dump: {
            Keychain.Result(status: 1, stdout: "", stderr: "User interaction is not allowed.")
        })) { error in
            XCTAssertTrue("\(error)".contains("list parked logins"))
        }
    }

    func testAFailedDumpThatStillPrintedSomethingIsRefused() {
        XCTAssertThrowsError(try Keychain.parkedAccountIDs(account: mine, dump: {
            Keychain.Result(status: 36, stdout: self.item(account: self.mine,
                                                          service: Slot.parked("A-1")),
                            stderr: "partial")
        }))
    }

    func testASuccessfulDumpIsRead() throws {
        let ids = try Keychain.parkedAccountIDs(account: mine, dump: {
            Keychain.Result(status: 0,
                            stdout: self.item(account: self.mine,
                                              service: Slot.parked("A-1")),
                            stderr: "")
        })
        XCTAssertEqual(ids, ["A-1"])
    }

    func testASuccessfulDumpThatIsGenuinelyEmptyListsNothing() throws {
        let ids = try Keychain.parkedAccountIDs(account: mine, dump: {
            Keychain.Result(status: 0, stdout: "", stderr: "")
        })
        XCTAssertEqual(ids, [])
    }
}
