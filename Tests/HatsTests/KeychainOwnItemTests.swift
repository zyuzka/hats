import XCTest
@testable import Hats

final class KeychainOwnItemTests: XCTestCase {
    private final class Steps {
        var order: [String] = []
        var added: Data?
        var addStatus: OSStatus = errSecSuccess
        var readBack: Keychain.OwnRead?
        var failRemoveOf: String?
        var renameStatus: OSStatus = errSecSuccess
    }

    private let parked = Slot.parked("A-1")

    private var staging: String { Keychain.stagingName(for: parked) }

    private func park(_ data: Data, service: String? = nil, steps: Steps) throws {
        try Keychain.writeOwnItem(
            service: service ?? parked,
            account: "me",
            data: data,
            remove: { name, _ in
                steps.order.append("remove \(name)")
                if name == steps.failRemoveOf { throw KeychainError(operation: "delete \(name)", detail: "refused") }
            },
            add: { item in
                steps.order.append("add \(item[kSecAttrService] as? String ?? "?")")
                steps.added = item[kSecValueData] as? Data
                return steps.addStatus
            },
            readBack: { name, _ in
                steps.order.append("read \(name)")
                return steps.readBack ?? steps.added.map { .found($0) } ?? .missing
            },
            rename: { from, to, _ in
                steps.order.append("rename \(from) -> \(to)")
                return steps.renameStatus
            }
        )
    }

    func testParkingWritesTheNewValueReadsItBackAndOnlyThenRemovesTheOldItem() throws {
        let steps = Steps()
        let data = Data("{\"token\":\"x\"}".utf8)

        try park(data, steps: steps)

        XCTAssertEqual(steps.added, data)
        XCTAssertEqual(steps.order, [
            "remove \(staging)",
            "add \(staging)",
            "read \(staging)",
            "remove \(parked)",
            "rename \(staging) -> \(parked)",
        ])
    }

    func testAFailedAddThrowsWithItsStatusAndKeepsTheOldItem() {
        let steps = Steps()
        steps.addStatus = errSecDuplicateItem

        XCTAssertThrowsError(try park(Data("new".utf8), steps: steps)) {
            XCTAssertTrue(
                $0.localizedDescription.contains("\(errSecDuplicateItem)"),
                "the message names the status: \($0.localizedDescription)"
            )
        }
        XCTAssertEqual(steps.order, ["remove \(staging)", "add \(staging)"], "the old item must not be removed")
    }

    func testAValueThatReadsBackDifferentRemovesTheStagingItemAndKeepsTheOldOne() {
        let steps = Steps()
        steps.readBack = .found(Data("other".utf8))

        XCTAssertThrowsError(try park(Data("new".utf8), steps: steps))
        XCTAssertEqual(
            steps.order,
            [
                "remove \(staging)",
                "add \(staging)",
                "read \(staging)",
                "remove \(staging)",
            ],
            "the staging item goes and the old item stays"
        )
    }

    func testAFailedRemoveOfTheOldItemRemovesTheStagingItemAndThrows() {
        let steps = Steps()
        steps.failRemoveOf = Slot.parked("A-1")

        XCTAssertThrowsError(try park(Data("new".utf8), steps: steps))
        XCTAssertEqual(Array(steps.order.suffix(2)), ["remove \(parked)", "remove \(staging)"])
        XCTAssertFalse(steps.order.contains { $0.hasPrefix("rename") }, "nothing is renamed over an old item")
    }

    func testAFailedRenameThrowsNamingTheStatusAndWhereTheValueIs() {
        let steps = Steps()
        steps.renameStatus = errSecDuplicateItem

        XCTAssertThrowsError(try park(Data("new".utf8), steps: steps)) {
            let text = $0.localizedDescription
            XCTAssertTrue(text.contains("\(errSecDuplicateItem)"), "the message names the status: \(text)")
            XCTAssertTrue(text.contains(self.staging), "the message says where the value is: \(text)")
        }
    }

    func testACodexItemOfFourKilobytesIsAddedWhole() throws {
        let steps = Steps()
        let service = Slot.codexParked("C-1")
        let data = Data(repeating: 0x7a, count: 4220)

        try park(data, service: service, steps: steps)

        XCTAssertEqual(Keychain.route(for: service), .hatsOwned)
        XCTAssertEqual(steps.added?.count, 4220)
        XCTAssertEqual(steps.added, data)
    }

    func testAStagingItemIsNeverListedAsAHat() {
        let names = [Slot.parked("A-1"), Slot.legacyParked("A-1"), Slot.codexParked("C-1")].map(Keychain.stagingName)
        var dump = ""
        for name in names + [Slot.parked("B-2"), Slot.codexParked("D-4")] {
            dump += "keychain: \"/k\"\nattributes:\n    \"acct\"<blob>=\"me\"\n    \"svce\"<blob>=\"\(name)\"\n"
        }
        for name in names {
            XCTAssertFalse(Slot.hatsOwnedPrefixes.contains(where: name.hasPrefix), name)
        }

        XCTAssertEqual(Keychain.parsedParkedIDs(dump: dump, account: "me"), ["B-2"])
        XCTAssertEqual(Keychain.parsedParkedIDs(dump: dump, account: "me", prefixes: [Slot.codexParked("")]), ["D-4"])
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
