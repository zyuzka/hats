import XCTest
@testable import Hats

final class KeychainOwnItemTests: XCTestCase {
    private final class Calls {
        var order: [String] = []
        var added: Data?
        var removeArguments: [String] = []
    }

    private func park(
        _ data: Data,
        service: String = Slot.parked("A-1"),
        removeStatus: Int32,
        addStatus: OSStatus = errSecSuccess,
        calls: Calls
    ) throws {
        try Keychain.writeOwnItem(
            service: service,
            account: "me",
            data: data,
            remove: { arguments in
                calls.order.append("remove")
                calls.removeArguments = arguments
                return Keychain.Result(status: removeStatus, stdout: "", stderr: "remove said \(removeStatus)")
            },
            add: { item in
                calls.order.append("add")
                calls.added = item[kSecValueData] as? Data
                return addStatus
            }
        )
    }

    func testParkingWithNoPriorItemAddsTheExactData() throws {
        let calls = Calls()
        let data = Data("{\"token\":\"x\"}".utf8)

        try park(data, removeStatus: 44, calls: calls)

        XCTAssertEqual(calls.added, data)
        XCTAssertEqual(calls.removeArguments, ["delete-generic-password", "-s", Slot.parked("A-1"), "-a", "me"])
    }

    func testParkingOverAnOldItemRemovesItBeforeAdding() throws {
        let calls = Calls()

        try park(Data("new".utf8), removeStatus: 0, calls: calls)

        XCTAssertEqual(calls.order, ["remove", "add"])
    }

    func testAFailedRemoveThrowsAndNothingIsAdded() {
        let calls = Calls()

        XCTAssertThrowsError(try park(Data("new".utf8), removeStatus: 51, calls: calls))
        XCTAssertEqual(calls.order, ["remove"], "add must not run once the old item could not be removed")
    }

    func testAFailedAddThrowsWithItsStatus() {
        let calls = Calls()

        let failing = { try self.park(Data("new".utf8), removeStatus: 0, addStatus: errSecDuplicateItem, calls: calls) }
        XCTAssertThrowsError(try failing()) {
            XCTAssertTrue(
                $0.localizedDescription.contains("\(errSecDuplicateItem)"),
                "the message names the status: \($0.localizedDescription)"
            )
        }
    }

    func testACodexItemOfFourKilobytesIsAddedWhole() throws {
        let calls = Calls()
        let service = Slot.codexParked("C-1")
        let data = Data(repeating: 0x7a, count: 4220)

        try park(data, service: service, removeStatus: 44, calls: calls)

        XCTAssertEqual(Keychain.route(for: service), .hatsOwned)
        XCTAssertEqual(calls.added?.count, 4220)
        XCTAssertEqual(calls.added, data)
    }

    private func read(own: Keychain.OwnRead, findPrints: String = "", found: inout [[String]]) throws -> Data? {
        var seen: [[String]] = []
        defer { found = seen }
        return try Keychain.read(
            service: Slot.parked("A-1"),
            account: "me",
            readOwn: { _, _ in own },
            find: { arguments in
                seen.append(arguments)
                return Keychain.Result(status: 0, stdout: findPrints, stderr: "")
            }
        )
    }

    func testAnItemTheAPIReadsIsReturnedWithoutRunningSecurity() throws {
        var finds: [[String]] = []

        let value = try read(own: .found(Data("own".utf8)), findPrints: "other", found: &finds)

        XCTAssertEqual(value, Data("own".utf8))
        XCTAssertEqual(finds, [], "security find must not run when the API read the item")
    }

    func testAnItemTheAPIDoesNotFindIsNilWithoutRunningSecurity() throws {
        var finds: [[String]] = []

        let value = try read(own: .missing, findPrints: "other", found: &finds)

        XCTAssertNil(value)
        XCTAssertEqual(finds, [], "security find must not run when the API found no item")
    }

    func testARefusedItemThatSecurityDoesNotFindIsNil() throws {
        let value = try Keychain.read(
            service: Slot.parked("A-1"),
            account: "me",
            readOwn: { _, _ in .refused(errSecAuthFailed) },
            find: { _ in Keychain.Result(status: 44, stdout: "", stderr: "could not be found") }
        )

        XCTAssertNil(value)
    }

    func testACarriageReturnInANameIsRefused() {
        XCTAssertThrowsError(try Keychain.createInteractiveAddCommand(
            service: "S\r",
            account: "me",
            data: Data("x".utf8)
        ))
        XCTAssertThrowsError(try Keychain.createInteractiveAddCommand(
            service: "S",
            account: "m\re",
            data: Data("x".utf8)
        ))
    }

    func testAnItemTheAPIIsRefusedFallsBackToSecurity() throws {
        var finds: [[String]] = []

        let value = try read(own: .refused(errSecAuthFailed), findPrints: "legacy", found: &finds)

        XCTAssertEqual(value, Data("legacy".utf8))
        XCTAssertEqual(finds, [["find-generic-password", "-s", Slot.parked("A-1"), "-a", "me", "-w"]])
    }
}
