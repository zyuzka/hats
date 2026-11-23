import XCTest
@testable import Hats

final class KeychainOwnItemTests: XCTestCase {
    private let parked = Slot.parked("A-1")

    private var staging: String { Keychain.stagingName(for: parked) }

    private func park(_ data: Data, service: String? = nil, store: KeychainItemStore) throws {
        try Keychain.writeOwnItem(
            service: service ?? parked,
            account: "me",
            data: data,
            remove: { name, _ in try store.remove(name) },
            add: { store.add($0) },
            readBack: { name, _ in store.read(name) },
            rename: { from, to, _ in store.rename(from, to) }
        )
    }

    private func storeWithOldItem() -> KeychainItemStore {
        let store = KeychainItemStore()
        store.items[parked] = Data("old".utf8)

        return store
    }

    func testParkingWritesTheNewValueReadsItBackAndOnlyThenRemovesTheOldItem() throws {
        let store = storeWithOldItem()
        let data = Data("{\"token\":\"x\"}".utf8)

        try park(data, store: store)

        XCTAssertEqual(store.added, data)
        XCTAssertEqual(store.order, [
            "read \(parked)",
            "remove \(staging)",
            "add \(staging)",
            "read \(staging)",
            "remove \(parked)",
            "rename \(staging) -> \(parked)",
        ])
        XCTAssertEqual(store.items, [parked: data])
    }

    func testALeftoverStagingItemBesideTheRealOneIsRemoved() throws {
        let store = storeWithOldItem()
        store.items[staging] = Data("leftover".utf8)

        try park(Data("new".utf8), store: store)

        XCTAssertEqual(Array(store.order.prefix(3)), ["read \(parked)", "remove \(staging)", "add \(staging)"])
        XCTAssertEqual(store.items, [parked: Data("new".utf8)])
    }

    func testAStagingItemLeftAloneIsRenamedBackBeforeTheWrite() throws {
        let store = KeychainItemStore()
        store.items[staging] = Data("interrupted".utf8)

        try park(Data("new".utf8), store: store)

        XCTAssertEqual(store.order, [
            "read \(parked)",
            "read \(staging)",
            "rename \(staging) -> \(parked)",
            "remove \(staging)",
            "add \(staging)",
            "read \(staging)",
            "remove \(parked)",
            "rename \(staging) -> \(parked)",
        ])
        XCTAssertEqual(store.items, [parked: Data("new".utf8)])
    }

    func testAStagingItemThatCannotBeRenamedBackStopsTheWriteAndIsKept() {
        let store = KeychainItemStore()
        store.items[staging] = Data("interrupted".utf8)
        store.renameStatus = errSecDuplicateItem

        XCTAssertThrowsError(try park(Data("new".utf8), store: store))
        XCTAssertEqual(store.items, [staging: Data("interrupted".utf8)], "the only copy of the login must stay")
    }

    func testAFailedAddThrowsWithItsStatusAndKeepsTheOldItem() {
        let store = storeWithOldItem()
        store.addStatus = errSecDuplicateItem

        XCTAssertThrowsError(try park(Data("new".utf8), store: store)) {
            XCTAssertTrue(
                $0.localizedDescription.contains("\(errSecDuplicateItem)"),
                "the message names the status: \($0.localizedDescription)"
            )
        }
        XCTAssertEqual(
            store.order,
            ["read \(parked)", "remove \(staging)", "add \(staging)"],
            "the old item must not be removed"
        )
        XCTAssertEqual(store.items, [parked: Data("old".utf8)])
    }

    func testAValueThatReadsBackDifferentRemovesTheStagingItemAndKeepsTheOldOne() {
        let store = storeWithOldItem()
        store.readOverride[staging] = .found(Data("other".utf8))

        XCTAssertThrowsError(try park(Data("new".utf8), store: store))
        XCTAssertEqual(
            store.order,
            [
                "read \(parked)",
                "remove \(staging)",
                "add \(staging)",
                "read \(staging)",
                "remove \(staging)",
            ],
            "the staging item goes and the old item stays"
        )
        XCTAssertEqual(store.items, [parked: Data("old".utf8)])
    }

    func testAFailedRemoveOfTheOldItemRemovesTheStagingItemAndThrows() {
        let store = storeWithOldItem()
        store.failRemoveOf = parked

        XCTAssertThrowsError(try park(Data("new".utf8), store: store))
        XCTAssertEqual(Array(store.order.suffix(2)), ["remove \(parked)", "remove \(staging)"])
        XCTAssertFalse(store.order.contains { $0.hasPrefix("rename") }, "nothing is renamed over an old item")
    }

    func testAFailedRenameThrowsNamingTheStatusAndWhereTheValueIs() {
        let store = storeWithOldItem()
        store.renameStatus = errSecDuplicateItem

        XCTAssertThrowsError(try park(Data("new".utf8), store: store)) {
            let text = $0.localizedDescription
            XCTAssertTrue(text.contains("\(errSecDuplicateItem)"), "the message names the status: \(text)")
            XCTAssertTrue(text.contains(self.staging), "the message says where the value is: \(text)")
        }
    }

    func testACodexItemOfFourKilobytesIsAddedWhole() throws {
        let store = KeychainItemStore()
        let service = Slot.codexParked("C-1")
        let data = Data(repeating: 0x7a, count: 4220)

        try park(data, service: service, store: store)

        XCTAssertEqual(Keychain.route(for: service), .hatsOwned)
        XCTAssertEqual(store.added?.count, 4220)
        XCTAssertEqual(store.items, [service: data])
    }

    private func readParked(from store: KeychainItemStore, finds: inout Int) throws -> Data? {
        var count = 0
        defer { finds = count }
        return try Keychain.read(
            service: parked,
            account: "me",
            readOwn: { name, _ in store.read(name) },
            find: { _ in
                count += 1
                return Keychain.Result(status: 0, stdout: "found", stderr: "")
            },
            rename: { from, to, _ in store.rename(from, to) }
        )
    }

    func testReadingAHatLeftOnlyUnderItsStagingNameRenamesItBack() throws {
        let store = KeychainItemStore()
        store.items[staging] = Data("interrupted".utf8)
        var finds = 0

        let value = try readParked(from: store, finds: &finds)

        XCTAssertEqual(value, Data("interrupted".utf8))
        XCTAssertEqual(store.items, [parked: Data("interrupted".utf8)])
        XCTAssertEqual(finds, 0, "security find must not run")
    }

    func testReadingAStagingItemThatCannotBeRenamedStillReturnsIt() throws {
        let store = KeychainItemStore()
        store.items[staging] = Data("interrupted".utf8)
        store.renameStatus = errSecDuplicateItem
        var finds = 0

        let value = try readParked(from: store, finds: &finds)

        XCTAssertEqual(value, Data("interrupted".utf8))
        XCTAssertEqual(store.items, [staging: Data("interrupted".utf8)], "the item stays where it is")
    }

    func testReadingAHatWithNeitherItemIsNil() throws {
        let store = KeychainItemStore()
        var finds = 0

        let value = try readParked(from: store, finds: &finds)

        XCTAssertNil(value)
        XCTAssertEqual(store.order, ["read \(parked)", "read \(staging)"])
        XCTAssertEqual(finds, 0, "security find must not run")
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

    func testACarriageReturnLineFeedPairInANameIsRefused() {
        XCTAssertThrowsError(try Keychain.createInteractiveAddCommand(
            service: "S\r\n",
            account: "me",
            data: Data("x".utf8)
        ))
        XCTAssertThrowsError(try Keychain.createInteractiveAddCommand(
            service: "S",
            account: "me\r\n",
            data: Data("x".utf8)
        ))
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
