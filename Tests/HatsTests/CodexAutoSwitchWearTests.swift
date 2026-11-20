import XCTest
@testable import Hats

final class CodexAutoSwitchWearTests: XCTestCase {
    private let home = CodexFixture.home()
    private let keychain = FakeKeychain()
    private let server = FakeCodexServer()
    private let work = CodexFixture.ticket("hat-work", CodexFixture.work)
    private let personal = CodexFixture.ticket("hat-personal", CodexFixture.personal)
    private let spare = CodexFixture.Person(user: "user-spare", account: "acct-spare", email: "spare@example.com")
    private lazy var third = CodexFixture.ticket("hat-spare", spare)
    private lazy var desk = CodexDesk(world: server.world(home: home, keychain: keychain))
    private let liveWork = CodexFixture.login(CodexFixture.work, refresh: "work-live")
    private let personalLogin = CodexFixture.login(CodexFixture.personal, refresh: "personal-1")

    override func setUpWithError() throws {
        try super.setUpWithError()
        try liveWork.write(to: home.auth)
        keychain.contents[Slot.codexParked(personal.id)] = personalLogin
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home.url)
    }

    private func live() -> Data? { try? Data(contentsOf: home.auth) }

    private func wear(_ target: CodexTicket, insteadOf expected: String) -> CodexAutoWear? {
        var outcome: CodexAutoWear?
        desk.wear(target, insteadOf: expected, among: [work, personal, third]) { outcome = $0 }
        return outcome
    }

    func testTheSpareIsWornWhenTheHatDecidedAboutIsStillOn() {
        desk.noteWorn(work.id)

        let outcome = wear(personal, insteadOf: work.id)

        guard case .worn(let worn, _)? = outcome else { return XCTFail("expected a wear, got \(String(describing: outcome))") }
        XCTAssertEqual(worn, .worn(target: personal.id, outgoing: work.id, parked: liveWork))
        XCTAssertEqual(live(), personalLogin)
    }

    func testAHatChangedByHandOrByTheGatewayBeforeTheWearCancelsIt() {
        desk.noteWorn(work.id)
        desk.noteWornHere(personal.id)

        XCTAssertEqual(wear(personal, insteadOf: work.id), .moved)
        XCTAssertEqual(live(), liveWork, "nothing was written")
    }

    func testALiveFileChangedOutsideHatsToAnotherHatCancelsTheWear() throws {
        desk.noteWorn(work.id)
        let liveSpare = CodexFixture.login(spare, refresh: "spare-live")
        try liveSpare.write(to: home.auth)

        XCTAssertEqual(wear(personal, insteadOf: work.id), .moved)
        XCTAssertEqual(live(), liveSpare, "the login the decision never looked at is left alone")
        XCTAssertNil(keychain.contents[Slot.codexParked(third.id)], "nothing was parked")
    }

    func testAMissingLiveFileCancelsTheWear() throws {
        desk.noteWorn(work.id)
        try FileManager.default.removeItem(at: home.auth)

        XCTAssertEqual(wear(personal, insteadOf: work.id), .moved)
        XCTAssertNil(live())
    }

    func testAWearThatFailsReportsItsReasonAndLeavesTheLiveFile() {
        desk.noteWorn(work.id)
        keychain.contents[Slot.codexParked(personal.id)] = nil

        guard case .failed(let reason)? = wear(personal, insteadOf: work.id) else { return XCTFail("expected a failure") }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertEqual(live(), liveWork)
    }
}

final class CodexAutoSwitchFaceTests: XCTestCase {
    private func hat(_ id: String, tool: Tool, vacation: Bool = false) -> Account {
        var hat = Account(id: id, email: "\(id)@example.com")
        hat.tool = tool
        hat.hasStoredCredentials = true
        hat.codexOwner = tool == .codex ? CodexOwner(userID: "u-\(id)", accountID: "a-\(id)") : nil
        if vacation { hat.vacationSince = Date() }
        return hat
    }

    private func snapshot(spareOnVacation: Bool = false) -> HatsSnapshot {
        var snapshot = HatsSnapshot()
        snapshot.rows = [HatRowState(hat: hat("claude", tool: .claudeCode), isWearing: true, usage: nil,
                                     usageTrouble: nil)]
        snapshot.codexRows = ClaudeDoors.codexRows(
            [hat("plus", tool: .codex), hat("business", tool: .codex, vacation: spareOnVacation)],
            worn: "plus"
        )
        return snapshot
    }

    private var record: AutoSwitchRecord {
        AutoSwitchRecord(firedAt: Date(timeIntervalSince1970: 1_800_000_000), from: "plus", to: "business", limit: .session, resetsAt: nil,
                         cause: .reachedALimit)
    }

    func testTheCodexHandoverFollowsTheCodexSwitch() throws {
        var shown = snapshot()
        let worn = try XCTUnwrap(shown.wearing(on: .codex))
        XCTAssertNil(shown.getHandover(for: worn), "the Codex switch is off")

        shown.settings.codexAutoSwitch.isOn = true
        XCTAssertEqual(shown.getHandover(for: worn), "next: business@example.com")
        XCTAssertNil(shown.getHandover(for: try XCTUnwrap(shown.codexRows.last)), "only under the worn hat")
    }

    func testTheClaudeSwitchAloneGivesNoCodexHandover() throws {
        var shown = snapshot()
        shown.settings.autoSwitch.isOn = true

        XCTAssertNil(shown.getHandover(for: try XCTUnwrap(shown.wearing(on: .codex))))
    }

    func testWithEveryOtherCodexHatOnVacationTheHandoverSaysSo() throws {
        var shown = snapshot(spareOnVacation: true)
        shown.settings.codexAutoSwitch.isOn = true

        XCTAssertEqual(shown.getHandover(for: try XCTUnwrap(shown.wearing(on: .codex))),
                       HatsCopy.noHandoverTheOthersAreOnVacation)
    }

    func testEachBannerShowsOnItsOwnTabOnly() {
        var shown = snapshot()
        shown.codexBanner = record
        shown.codexBannerFromTitle = "plus"

        XCTAssertEqual(shown.banner(on: .codex)?.record, record)
        XCTAssertNil(shown.banner(on: .claudeCode))

        shown.codexBanner = nil
        shown.banner = record
        XCTAssertNil(shown.banner(on: .codex))
        XCTAssertEqual(shown.banner(on: .claudeCode)?.record, record)
    }

    func testAnOlderSettingsFileLoadsWithTheCodexSwitchOff() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hats-settings-\(UUID().uuidString)/settings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"gatewayPort": 9000, "autoSwitch": {"isOn": true, "order": [], "notifies": true}}"#.utf8)
            .write(to: url)

        let settings = AppSettings.loaded(from: url)

        XCTAssertEqual(settings.gatewayPort, 9000, "the file was read, not replaced by the defaults")
        XCTAssertTrue(settings.autoSwitch.isOn)
        XCTAssertEqual(settings.codexAutoSwitch, AutoSwitchPolicy())
        XCTAssertFalse(settings.codexAutoSwitch.isOn)
        XCTAssertEqual(settings.codexAutoSwitch.sessionThresholdPercent, 90)
        XCTAssertEqual(settings.codexAutoSwitch.weeklyThresholdPercent, 95)
        XCTAssertNil(settings.codexAutoSwitchRecord)
    }

    func testTheCodexSwitchAndItsRecordSurviveASave() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hats-settings-\(UUID().uuidString)/settings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var settings = AppSettings()
        settings.codexAutoSwitch = AutoSwitchPolicy(isOn: true, sessionThresholdPercent: 80, order: ["business"])
        settings.codexAutoSwitchRecord = AutoSwitchRecord(firedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                                          from: "plus", to: "business", limit: .weekly,
                                                          resetsAt: nil, cause: .reachedALimit)
        try settings.save(to: url)

        let loaded = AppSettings.loaded(from: url)

        XCTAssertEqual(loaded.codexAutoSwitch, settings.codexAutoSwitch)
        XCTAssertEqual(loaded.codexAutoSwitchRecord, settings.codexAutoSwitchRecord)
        XCTAssertNil(loaded.autoSwitchRecord, "the Codex record is not the Claude one")
    }
}

final class CodexAutoSwitchRulesTests: XCTestCase {
    private let record = AutoSwitchRecord(firedAt: Date(timeIntervalSince1970: 1_800_000_000), from: "plus",
                                          to: "business", limit: .session, resetsAt: nil, cause: .reachedALimit)

    func testAFailedWearIsNotTriedAgainUntilATimerPollAndItsReasonIsWrittenOnChange() {
        var failures = CodexAutoSwitchFailures()
        XCTAssertTrue(failures.allows(from: "plus", to: "business"))

        XCTAssertTrue(failures.shouldWriteAFailure(from: "plus", to: "business", reason: "locked"))
        XCTAssertFalse(failures.allows(from: "plus", to: "business"))
        XCTAssertTrue(failures.allows(from: "plus", to: "team"), "another target is tried")

        failures.aTimerPollCame()
        XCTAssertTrue(failures.allows(from: "plus", to: "business"))
        XCTAssertFalse(failures.shouldWriteAFailure(from: "plus", to: "business", reason: "locked"), "the same reason again")
        XCTAssertTrue(failures.shouldWriteAFailure(from: "plus", to: "business", reason: "not stored"))

        failures.succeeded()
        XCTAssertTrue(failures.allows(from: "plus", to: "business"))
        XCTAssertTrue(failures.shouldWriteAFailure(from: "plus", to: "business", reason: "not stored"), "a new episode")
    }

    func testRemovingAHatClearsEveryRecordAndOrderThatNamesIt() {
        var settings = AppSettings()
        settings.autoSwitch.order = ["a", "business"]
        settings.codexAutoSwitch.order = ["business", "team"]
        settings.codexAutoSwitchRecord = record
        settings.autoSwitchRecord = AutoSwitchRecord(firedAt: record.firedAt, from: "a", to: "b", limit: .weekly,
                                                     resetsAt: nil, cause: .reachedALimit)

        settings.forgetInTheSwitches("business")
        XCTAssertEqual(settings.autoSwitch.order, ["a"])
        XCTAssertEqual(settings.codexAutoSwitch.order, ["team"])
        XCTAssertNil(settings.codexAutoSwitchRecord)
        XCTAssertNotNil(settings.autoSwitchRecord, "the Claude record names other hats")

        settings.codexAutoSwitchRecord = record
        settings.forgetInTheSwitches("a")
        XCTAssertNil(settings.autoSwitchRecord)
        XCTAssertEqual(settings.codexAutoSwitchRecord, record)

        settings.forgetInTheSwitches("plus")
        XCTAssertNil(settings.codexAutoSwitchRecord, "the hat it came from")
    }

    func testTheBannerCarriesItsOwnTool() {
        var snapshot = HatsSnapshot()
        snapshot.codexBanner = record
        snapshot.banner = record

        XCTAssertEqual(snapshot.banner(on: .codex)?.tool, .codex)
        XCTAssertEqual(snapshot.banner(on: .claudeCode)?.tool, .claudeCode)
    }
}
