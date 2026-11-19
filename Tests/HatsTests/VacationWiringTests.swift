import XCTest
@testable import Hats

final class VacationWiringTests: XCTestCase {
    private let since = Date(timeIntervalSince1970: 1_800_000_000)
    private var operations: [String] = []
    private var lines: [[String: String]] = []
    private let keychain = FakeKeychain()

    private func createIsolatedStore() throws -> AccountStore {
        let override = ProcessInfo.processInfo.environment[StateDirectory.overrideName] ?? ""
        try XCTSkipIf(
            override.isEmpty,
            "the store writes accounts.json through StateDirectory, and without HATS_STATE_HOME that is "
                + "the developer's own list of hats"
        )
        let store = AccountStore(osAccount: "vacation-wiring-test", keychain: keychain.world())
        store.journaling = { [unowned self] operation, line in
            operations.append(operation)
            lines.append(line)
        }

        return store
    }

    private func createHat(in store: AccountStore) throws -> Account {
        try store.add(email: "vacation-\(UUID().uuidString.prefix(8))@b.com", browser: nil)
    }

    private func withTheStateFolderReadOnly(_ body: () throws -> Void) throws {
        let folder = StateDirectory.url.path
        let permissions = try FileManager.default.attributesOfItem(atPath: folder)[.posixPermissions]
        let readOnly: [FileAttributeKey: Any] = [
            .posixPermissions: 0o500,
        ]
        let restored: [FileAttributeKey: Any] = [
            .posixPermissions: permissions ?? 0o700,
        ]
        try FileManager.default.setAttributes(readOnly, ofItemAtPath: folder)
        defer { try? FileManager.default.setAttributes(restored, ofItemAtPath: folder) }
        try body()
    }

    func testTheVacationLineCarriesTheHatTheStateAndTheStart() {
        XCTAssertEqual(
            HatJournalLine.vacation(hat: "0123456789abcdef", on: true, since: since),
            [
                "hat": "01234567",
                "on": "true",
                "since": "2027-01-15T08:00:00Z",
            ]
        )
        XCTAssertEqual(
            HatJournalLine.vacation(hat: "0123456789abcdef", on: false, since: nil)["since"],
            "-"
        )
    }

    func testSettingAndEndingAVacationWritesTheLineWithTheStartDate() throws {
        let store = try createIsolatedStore()
        let hat = try createHat(in: store)

        try store.setVacation(hat.id, on: true, at: since)
        try store.setVacation(hat.id, on: false, at: since.addingTimeInterval(7200))

        XCTAssertEqual(operations, ["hat.vacation", "hat.vacation"])
        XCTAssertEqual(lines, [
            HatJournalLine.vacation(hat: hat.id, on: true, since: since),
            HatJournalLine.vacation(hat: hat.id, on: false, since: since),
        ], "ending a vacation names the day it began, not the day it ended")
    }

    func testAFailedWriteLeavesNoVacationLine() throws {
        let store = try createIsolatedStore()
        let hat = try createHat(in: store)

        try withTheStateFolderReadOnly {
            XCTAssertThrowsError(try store.setVacation(hat.id, on: true, at: since))
        }

        XCTAssertEqual(operations, [], "the journal never reports a vacation the file does not hold")
    }

    func testRemovingAHatWritesTheRemovalLine() throws {
        let store = try createIsolatedStore()
        _ = try createHat(in: store)
        let gone = try createHat(in: store)

        try store.remove(gone.id)

        XCTAssertEqual(operations, ["remove"])
        XCTAssertEqual(lines.first, HatJournalLine.removal(hat: gone.id, payload: nil, deletionError: nil))
        XCTAssertEqual(lines.first?["credentialDeleted"], "true")
        XCTAssertEqual(lines.first?["id"], String(gone.id.prefix(8)))
    }

    func testAKeyThatCouldNotBeDeletedIsJournaledWithItsFingerprintAndThrown() throws {
        let store = try createIsolatedStore()
        _ = try createHat(in: store)
        let gone = try createHat(in: store)
        let key = Data("parked-key".utf8)
        keychain.contents[Slot.parked(gone.id)] = key
        keychain.deleteFailures.insert(Slot.parked(gone.id))

        XCTAssertThrowsError(try store.remove(gone.id)) { error in
            guard case SwitchError.credentialNotDeleted = error else {
                return XCTFail("expected credentialNotDeleted, got \(error)")
            }
        }

        XCTAssertEqual(operations, ["remove"])
        XCTAssertEqual(lines.first?["payload"], Journal.fingerprint(key))
        XCTAssertEqual(lines.first?["credentialDeleted"], "failed")
        XCTAssertNotEqual(lines.first?["deletionFailure"], "none")
    }

    func testTheRemovalLineSaysWhenTheCredentialStayed() {
        let failure = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "locked"])

        XCTAssertEqual(
            HatJournalLine.removal(hat: "0123456789abcdef", payload: Data("x".utf8), deletionError: failure),
            [
                "id": "01234567",
                "payload": Journal.fingerprint(Data("x".utf8)),
                "credentialDeleted": "failed",
                "deletionFailure": "locked",
            ]
        )
    }

    private struct Counts {
        var redraws = 0
        var polls = 0
        var errors: [String] = []
    }

    private func apply(_ id: String, on: Bool, in store: AccountStore) -> Counts {
        var counts = Counts()
        VacationChange(
            redraw: { counts.redraws += 1 },
            poll: { counts.polls += 1 },
            sayItCouldNotSave: { counts.errors.append($0.localizedDescription) }
        ).apply(id, on: on, at: since, in: store)

        return counts
    }

    func testAChangedVacationRedrawsAndAsksForOnePoll() throws {
        let store = try createIsolatedStore()
        let hat = try createHat(in: store)

        let counts = apply(hat.id, on: true, in: store)

        XCTAssertEqual(counts.polls, 1, "the warning is recomputed only when a poll lands")
        XCTAssertEqual(counts.redraws, 1)
        XCTAssertEqual(counts.errors, [])
    }

    func testAVacationThatCouldNotBeSavedAsksForNoPollAndSaysSo() throws {
        let store = try createIsolatedStore()
        let hat = try createHat(in: store)
        var counts = Counts()

        try withTheStateFolderReadOnly {
            counts = apply(hat.id, on: true, in: store)
        }

        XCTAssertEqual(counts.polls, 0, "nothing changed, so there is nothing to poll for")
        XCTAssertEqual(counts.redraws, 1, "the checkbox goes back to what the file holds")
        XCTAssertEqual(counts.errors.count, 1)
    }

    func testTheAppHandsTheVacationChangeItsPollAndItsDialog() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/AppDelegate+Actions.swift")
        let actions = try String(contentsOf: source, encoding: .utf8)
        let start = try XCTUnwrap(actions.range(of: "func setVacation(")).lowerBound
        let rest = actions[start...]
        let setting = String(rest[..<(rest.range(of: "\n    }\n")?.lowerBound ?? rest.endIndex)])

        XCTAssertTrue(setting.contains("VacationChange("))
        XCTAssertTrue(setting.contains("self.usage.poll(self.hatsForUsage())"))
        XCTAssertTrue(setting.contains("HatDialogs.present($0, title: \"Could not save that change\")"))
        XCTAssertTrue(setting.contains(".apply(id, on: on, at: Date(), in: store)"))
    }

    private func createSnapshot(_ hats: [Account]) -> HatsSnapshot {
        var snapshot = HatsSnapshot()
        snapshot.settings.isGatewayEnabled = false
        snapshot.settings.autoSwitch.isOn = true
        snapshot.rows = hats.map {
            HatRowState(
                hat: $0,
                isWearing: $0.id == "a",
                usage: $0.id == "a" ? UsageReading(
                    session: UsageWindow(used: 10, limit: 100, resetsAt: nil),
                    weekly: nil
                ) : nil,
                usageTrouble: nil,
                now: since,
                timeZone: TimeZone(identifier: "UTC")!
            )
        }

        return snapshot
    }

    private func createHat(_ id: String, signedIn: Bool = true, away: Bool = false) -> Account {
        var hat = Account(id: id, email: "\(id)@x.co", browser: nil)
        hat.name = id.uppercased()
        if signedIn {
            hat.hasStoredCredentials = true
            hat.identity = CLIIdentity(oauthAccount: [:], userID: nil)
        }
        if away { hat.vacationSince = since }

        return hat
    }

    func testTheAttentionDotLightsForAHatThatNeedsALoginAndNotForOneOnVacation() {
        let blocked = createSnapshot([createHat("a"), createHat("c", signedIn: false)])
        let away = createSnapshot([createHat("a"), createHat("c", signedIn: false, away: true)])

        XCTAssertEqual(blocked.markState, .attention)
        XCTAssertEqual(away.markState, .wearing(percent: 10), "a hat the switch is not using lights no dot")
    }
}
