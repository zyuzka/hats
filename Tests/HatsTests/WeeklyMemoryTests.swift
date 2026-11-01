import XCTest
@testable import Hats

final class WeeklyMemoryTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hats-weekly-\(UUID().uuidString)/weekly.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        super.tearDown()
    }

    private func date(_ text: String) throws -> Date { try XCTUnwrap(UsageReading.date(from: text)) }

    private func week(_ used: Int, resets: Date?) -> UsageWindow {
        UsageWindow(used: used, limit: 100, resetsAt: resets)
    }

    private func reading(session: Int? = 10, weekly: UsageWindow?) -> UsageReading {
        UsageReading(session: session.map { UsageWindow(used: $0, limit: 100, resetsAt: nil) }, weekly: weekly)
    }

    private func line(_ sighting: WeekSighting?, now: Date) -> String? {
        sighting.map {
            HatsCopy.weekLine(
                percent: $0.window.percent,
                resetsAt: $0.window.resetsAt,
                isConfirmed: $0.isConfirmed,
                timeZone: utc,
                now: now
            )
        }
    }

    private func hat(_ id: String) -> Account {
        var hat = Account(id: id, email: "\(id)@company.com", browser: nil)
        hat.hasStoredCredentials = true
        hat.identity = CLIIdentity(oauthAccount: [:], userID: nil)
        return hat
    }

    func testTheWeekLineCarriesTheResetDateAndAMarkWhenUnconfirmed() throws {
        let now = try date("2026-10-28T12:00:00Z")
        let resets = try date("2026-11-02T14:00:00Z")

        XCTAssertEqual(HatsCopy.weekLine(percent: 1, resetsAt: resets, isConfirmed: true, timeZone: utc, now: now),
                       "week 1% (Mon 2 Nov 14:00)")
        XCTAssertEqual(HatsCopy.weekLine(percent: 1, resetsAt: resets, isConfirmed: false, timeZone: utc, now: now),
                       "week 1% (Mon 2 Nov 14:00)?",
                       "a number no poll confirmed may be stale, and the row has to say so")
        XCTAssertEqual(HatsCopy.weekLine(percent: 1, resetsAt: nil, isConfirmed: true, timeZone: utc, now: now),
                       "week 1%")
        XCTAssertEqual(HatsCopy.weekLine(percent: 1, resetsAt: nil, isConfirmed: false, timeZone: utc, now: now),
                       "week 1%?")
    }

    func testAResetAlreadyPastHidesTheNumberConfirmedOrNot() throws {
        let now = try date("2026-10-28T12:00:00Z")
        let passed = try date("2026-10-27T11:00:00Z")

        for confirmed in [true, false] {
            XCTAssertEqual(HatsCopy.weekLine(percent: 40, resetsAt: passed, isConfirmed: confirmed,
                                             timeZone: utc, now: now),
                           "week ? (Tue 27 Oct 11:00)",
                           "the week has reset since, so the spend since then is unknown")
        }
        XCTAssertEqual(HatsCopy.weekLine(percent: 40, resetsAt: now, isConfirmed: true, timeZone: utc, now: now),
                       "week ? (Wed 28 Oct 12:00)", "a reset at this very second is a reset")
    }

    func testTheDateIsLocalTime() throws {
        let now = try date("2026-10-28T12:00:00Z")
        let kyiv = try XCTUnwrap(TimeZone(identifier: "Europe/Kyiv"))

        XCTAssertEqual(HatsCopy.weekLine(percent: 1, resetsAt: try date("2026-11-02T14:00:00Z"),
                                         isConfirmed: true, timeZone: kyiv, now: now),
                       "week 1% (Mon 2 Nov 16:00)")
    }

    func testTheMatrix() throws {
        let now = try date("2026-10-28T12:00:00Z")
        let resets = try date("2026-11-02T14:00:00Z")
        let remembered = WeeklyMemory().remembering(["a": reading(weekly: week(1, resets: resets))], fresh: ["a"])

        XCTAssertEqual(line(remembered.findSighting(of: "a", readings: ["a": reading(weekly: week(1, resets: resets))],
                                                    fresh: ["a"]), now: now),
                       "week 1% (Mon 2 Nov 14:00)", "a fresh poll")
        XCTAssertEqual(line(remembered.findSighting(of: "a", readings: ["a": reading(weekly: week(1, resets: resets))],
                                                    fresh: []), now: now),
                       "week 1% (Mon 2 Nov 14:00)?", "the poll failed, or the renewal was put off")
        XCTAssertEqual(line(remembered.findSighting(of: "a", readings: [:], fresh: []), now: now),
                       "week 1% (Mon 2 Nov 14:00)?", "after a restart, or a trouble that cleared the reading")
        XCTAssertEqual(line(remembered.findSighting(of: "a", readings: ["a": reading(weekly: nil)], fresh: ["a"]),
                            now: now),
                       "week 1% (Mon 2 Nov 14:00)?", "an answer without the week confirms nothing about it")
        XCTAssertNil(WeeklyMemory().findSighting(of: "a", readings: ["a": reading(weekly: nil)], fresh: ["a"]),
                     "nothing known, no week line")
    }

    func testOnlyAFreshWeekIsRememberedAndAWeeklessAnswerKeepsTheOldOne() throws {
        let resets = try date("2026-11-02T14:00:00Z")
        let first = WeeklyMemory().remembering(["a": reading(weekly: week(1, resets: resets)),
                                                "b": reading(weekly: week(9, resets: resets))],
                                               fresh: ["a"])

        XCTAssertEqual(first.hats, ["a": week(1, resets: resets)],
                       "b's reading was kept from an earlier poll, so it is nothing new")
        XCTAssertEqual(first.remembering(["a": reading(weekly: nil)], fresh: ["a"]), first)
    }

    func testTheFileRoundTripsAndABrokenOrMissingFileIsNothingKnown() throws {
        let resets = try date("2026-11-02T14:00:00.123Z")
        let memory = WeeklyMemory().remembering(["a": reading(weekly: week(7, resets: resets)),
                                                 "b": reading(weekly: week(3, resets: nil))],
                                                fresh: ["a", "b"])

        XCTAssertEqual(WeeklyMemory.loaded(from: url), WeeklyMemory())
        try memory.save(to: url)
        XCTAssertEqual(WeeklyMemory.loaded(from: url), memory)

        try Data("{ not json".utf8).write(to: url)
        XCTAssertEqual(WeeklyMemory.loaded(from: url), WeeklyMemory())
    }

    func testDamagedEntriesAreDroppedRatherThanShownAsAnInventedPercent() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let damaged = #"{"hats":{"negative":{"used":-5,"limit":100},"over":{"used":500,"limit":100},"#
            + #""noLimit":{"used":5,"limit":0},"belowZero":{"used":0,"limit":-1},"#
            + #""huge":{"used":100000000000000000,"limit":100},"#
            + #""hugeBoth":{"used":100000000000000000,"limit":100000000000000000},"#
            + #""fine":{"used":41,"limit":100}}}"#
        try Data(damaged.utf8).write(to: url)

        let memory = WeeklyMemory.loaded(from: url)

        XCTAssertEqual(memory.hats, ["fine": week(41, resets: nil)],
                       "a number the server could not have sent is not a number; the huge ones "
                           + "would overflow percent and crash the app on every launch")
        XCTAssertEqual(memory.hats["fine"]?.percent, 41)
    }

    func testTheLiveHatsAreUnknownOnlyWhenTheIndexIsUnusable() {
        XCTAssertNil(WeeklyRecord.findLiveIDs([], indexIsUnusable: true))
        XCTAssertNil(WeeklyRecord.findLiveIDs(["a"], indexIsUnusable: true))
        XCTAssertEqual(WeeklyRecord.findLiveIDs([], indexIsUnusable: false), [],
                       "the last hat was removed, so its entry has to leave the file")
        XCTAssertEqual(WeeklyRecord.findLiveIDs(["a", "b"], indexIsUnusable: false), ["a", "b"])
    }

    func testTheAppRemembersTheWeekOnEveryPollAndShowsItOnEveryRow() throws {
        let main = sourceOf("main.swift")
        let onReadings = String(main[try XCTUnwrap(main.range(of: "usage.onReadings = {")).lowerBound...])
            .prefix(200)
        let redraw = sourceOf("AppDelegate+Redraw.swift")

        XCTAssertTrue(onReadings.contains("self?.rememberTheWeek()"),
                      "a poll that lands has to reach the memory, or nothing is remembered or written")
        XCTAssertTrue(redraw.contains("week: weekly.memory.findSighting(of: hat.id, readings: usage.readings, "
                                          + "fresh: usage.freshInTheLastPoll)"),
                      "the row takes the week from here; the parameter has a default, so dropping "
                          + "it would compile and show no week anywhere")
        XCTAssertTrue(redraw.contains("WeeklyRecord.findLiveIDs(store.accounts.map(\\.id), "
                                          + "indexIsUnusable: store.indexUnusable != nil)"),
                      "the file is cut by the hats the store holds, and held only when their index "
                          + "could not be read")
    }

    private func sourceOf(_ name: String) -> String {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Hats/\(name)")

        return (try? String(contentsOf: source, encoding: .utf8)) ?? ""
    }

    func testARecordWritesOnlyWhatChangedAndDropsRemovedHats() throws {
        let resets = try date("2026-11-02T14:00:00Z")
        var record = WeeklyRecord(url: url)

        XCTAssertEqual(record.noteAPoll(["a": reading(weekly: week(1, resets: resets))], fresh: ["a"],
                                        liveIDs: ["a", "b"]),
                       .written)
        XCTAssertEqual(record.noteAPoll(["a": reading(weekly: week(1, resets: resets))], fresh: ["a"],
                                        liveIDs: ["a", "b"]),
                       .unchanged)
        XCTAssertEqual(record.noteAPoll(["b": reading(weekly: week(2, resets: resets))], fresh: ["b"],
                                        liveIDs: ["b"]),
                       .written)
        XCTAssertEqual(WeeklyMemory.loaded(from: url).hats, ["b": week(2, resets: resets)],
                       "a hat that was removed leaves the file at the next write")
        XCTAssertEqual(WeeklyRecord(url: url).memory, record.memory, "a restart reads back what was written")
    }

    func testAResetDateThatOnlyJittersBelowASecondDoesNotRewriteTheFile() throws {
        let first = try date("2026-11-02T14:00:00.369Z")
        let second = try date("2026-11-02T13:59:59.804Z")
        var record = WeeklyRecord(url: url)

        XCTAssertEqual(record.noteAPoll(["a": reading(weekly: week(1, resets: first))], fresh: ["a"], liveIDs: ["a"]),
                       .written)
        XCTAssertEqual(record.noteAPoll(["a": reading(weekly: week(1, resets: second))], fresh: ["a"], liveIDs: ["a"]),
                       .unchanged,
                       "the server sends the same reset with a different fraction of a second on every poll, "
                           + "and storing it as sent rewrote weekly.json every 300 s")
        XCTAssertEqual(WeeklyMemory.loaded(from: url).hats["a"]?.resetsAt, try date("2026-11-02T14:00:00Z"))
    }

    func testAnUnreadableIndexLeavesTheFileAlone() throws {
        let resets = try date("2026-11-02T14:00:00Z")
        var record = WeeklyRecord(url: url)
        _ = record.noteAPoll(["a": reading(weekly: week(1, resets: resets))], fresh: ["a"], liveIDs: ["a"])
        let before = try Data(contentsOf: url)

        XCTAssertEqual(record.noteAPoll(["b": reading(weekly: week(5, resets: resets))], fresh: ["b"], liveIDs: nil),
                       .heldBecauseTheHatsAreUnknown)
        XCTAssertEqual(try Data(contentsOf: url), before,
                       "with no hats known every entry would look removed, so nothing is cut or rewritten")
        XCTAssertNotNil(record.memory.hats["b"], "the screen still gets the new number")
    }

    func testAFailedWriteIsTriedAgainOnTheNextPoll() throws {
        let resets = try date("2026-11-02T14:00:00Z")
        let blocker = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: blocker.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: blocker)
        var record = WeeklyRecord(url: url)
        let poll = ["a": reading(weekly: week(1, resets: resets))]

        guard case .failed = record.noteAPoll(poll, fresh: ["a"], liveIDs: ["a"]) else {
            return XCTFail("a file where the directory should be cannot be written into")
        }
        try FileManager.default.removeItem(at: blocker)
        XCTAssertEqual(record.noteAPoll(poll, fresh: ["a"], liveIDs: ["a"]), .written,
                       "the comparison is with the last version that reached the disk, not with memory")
    }

    func testTheRememberedWeekNeverReachesTheReadingsAutoSwitchUses() throws {
        let resets = try date("2026-11-02T14:00:00Z")
        let memory = WeeklyMemory().remembering(["a": reading(weekly: week(99, resets: resets))], fresh: ["a"])
        var snapshot = HatsSnapshot()
        snapshot.rows = [
            HatRowState(hat: hat("a"), isWearing: true, usage: nil, usageTrouble: nil,
                        week: memory.findSighting(of: "a", readings: [:], fresh: [])),
        ]

        XCTAssertNotNil(snapshot.rows[0].week)
        XCTAssertTrue(snapshot.readingByHat.isEmpty,
                      "a number read back from disk after a restart is for the eye only")
        XCTAssertNil(snapshot.wearing?.usage)
    }

    func testWearingAHatWhoseOutOfBandPollLandedDropsTheMark() throws {
        let now = try date("2026-10-28T12:00:00Z")
        let resets = try date("2026-11-02T14:00:00Z")
        let poll = ["a": reading(weekly: week(4, resets: resets))]
        let memory = WeeklyMemory().remembering(poll, fresh: ["a"])
        let before = HatRowState(hat: hat("a"), isWearing: false, usage: nil, usageTrouble: nil,
                                 week: memory.findSighting(of: "a", readings: [:], fresh: []),
                                 now: now, timeZone: utc)
        let after = HatRowState(hat: hat("a"), isWearing: true, usage: poll["a"], usageTrouble: nil,
                                week: memory.findSighting(of: "a", readings: poll, fresh: ["a"]),
                                now: now, timeZone: utc)

        XCTAssertEqual(before.week, "week 4% (Mon 2 Nov 14:00)?")
        XCTAssertEqual(after.week, "week 4% (Mon 2 Nov 14:00)")
    }
}
