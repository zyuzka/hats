import AppKit
import XCTest
@testable import Hats

final class HatUsageLimitFieldsTests: XCTestCase {
    private var folder: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let polledAt = Date(timeIntervalSince1970: 1_799_999_700)
    private let slot = "Claude Code-credentials-78553e2b"

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("hat-usage-limits-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func hat(_ id: String) -> Account {
        var hat = Account(id: id, email: "\(id)@company.com", browser: nil)
        hat.hasStoredCredentials = true
        hat.identity = CLIIdentity(oauthAccount: [:], userID: nil)

        return hat
    }

    private func snapshot(
        wearing: String?,
        hats: [String] = ["work", "personal"],
        autoSwitch: Bool = true,
        session: Int? = 90,
        weekly: Int? = 95
    ) -> HatsSnapshot {
        var snapshot = HatsSnapshot()
        snapshot.rows = hats.map { HatRowState(hat: hat($0), isWearing: $0 == wearing, usage: nil, usageTrouble: nil) }
        snapshot.settings.autoSwitch.isOn = autoSwitch
        snapshot.settings.autoSwitch.sessionThresholdPercent = session
        snapshot.settings.autoSwitch.weeklyThresholdPercent = weekly

        return snapshot
    }

    private func record(_ snapshot: HatsSnapshot, liveSlot: String?, aliveAt: Date?) -> HatUsageRecord {
        HatUsageRecord.create(from: snapshot, readAt: [:], liveSlot: liveSlot, aliveAt: aliveAt, stages: [])
    }

    private func fields(of record: HatUsageRecord) throws -> [String: Any] {
        var file = HatUsageFile(url: folder.appendingPathComponent(HatUsageFile.name))
        XCTAssertEqual(file.setRecord(record, at: now), .written)

        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
    }

    private func findNode() throws -> URL {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let folders = path.split(separator: ":").map(String.init) + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        for folder in folders {
            let node = URL(fileURLWithPath: folder).appendingPathComponent("node")
            if FileManager.default.isExecutableFile(atPath: node.path) { return node }
        }
        throw XCTSkip("node is not installed, so the mod's own reader cannot be run")
    }

    private func readByTheMod(_ url: URL) throws -> [String: Any] {
        let rules = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugin/hooks/limit-rules.js")
        let script = """
            import { readFileSync } from 'node:fs'
            import { findHatUsage, findWhy, isUnderHats } from '\(rules.path)'
            const usage = findHatUsage(readFileSync(process.argv[1], 'utf8'))
            const now = Date.parse(process.argv[2])
            const answer = usage === null ? { usage: null } : {
              worn: usage.worn,
              isUnderHats: isUnderHats(usage, process.argv[3]),
              fiveHour: findWhy(usage, 'five_hour', now),
              sevenDay: findWhy(usage, 'seven_day', now),
            }
            process.stdout.write(JSON.stringify(answer))
            """
        let process = Process()
        process.executableURL = try findNode()
        process.arguments = ["--input-type=module", "-e", script, url.path, HatUsageRecord.getStamp(polledAt), slot]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "the mod's reader ran")

        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheModReadsTheFileHatsWritesWithTheSameCellAndReasons() throws {
        let covering = record(snapshot(wearing: "work", weekly: nil), liveSlot: slot, aliveAt: polledAt)
        var file = HatUsageFile(url: folder.appendingPathComponent(HatUsageFile.name))
        XCTAssertEqual(file.setRecord(covering, at: now), .written)

        let read = try readByTheMod(file.url)

        XCTAssertEqual(read["worn"] as? String, "work")
        XCTAssertEqual(read["isUnderHats"] as? Bool, true)
        XCTAssertTrue(read["fiveHour"] is NSNull, "Hats switches on the 5-hour limit, so the mod leaves it: \(read)")
        XCTAssertEqual(read["sevenDay"] as? String, "switch_threshold_off")
    }

    func testWithOneHatTheModHearsThatThereIsNoOtherHatOnBothLimits() throws {
        let alone = record(snapshot(wearing: "work", hats: ["work"]), liveSlot: slot, aliveAt: polledAt)
        var file = HatUsageFile(url: folder.appendingPathComponent(HatUsageFile.name))
        XCTAssertEqual(file.setRecord(alone, at: now), .written)

        let read = try readByTheMod(file.url)

        XCTAssertEqual(read["isUnderHats"] as? Bool, true, "one hat is still a hat: the limit thresholds act")
        XCTAssertEqual(read["fiveHour"] as? String, "no_hat")
        XCTAssertEqual(read["sevenDay"] as? String, "no_hat")
    }

    func testAWornHatWithAKnownCellCarriesItsCellWhatHatsSwitchesOnAndTheTimeOfThePoll() throws {
        let written = try fields(of: record(snapshot(wearing: "work"), liveSlot: slot, aliveAt: polledAt))

        XCTAssertEqual(written["credential_service"] as? String, slot)
        let covers = try XCTUnwrap(written["switch_covers"] as? [String: Any])
        XCTAssertEqual(covers["five_hour"] as? Bool, true)
        XCTAssertEqual(covers["seven_day"] as? Bool, true)
        XCTAssertEqual(Set(covers.keys), ["five_hour", "seven_day"])
        XCTAssertEqual(written["alive_at"] as? String, "2027-01-15T07:55:00Z")
        XCTAssertEqual(written["worn"] as? String, "work", "the old fields keep their meaning")
        XCTAssertEqual(written["has_a_hat_to_switch_to"] as? Bool, true)
        XCTAssertEqual(written["auto_switch_on"] as? Bool, true)
    }

    func testNoHatWornLeavesTheCellNullEvenWhenItIsKnown() throws {
        let written = try fields(of: record(snapshot(wearing: nil), liveSlot: slot, aliveAt: polledAt))

        XCTAssertTrue(written["credential_service"] is NSNull, "\(String(describing: written["credential_service"]))")
        XCTAssertTrue(written["worn"] is NSNull)
    }

    func testAnUnknownCellIsNull() throws {
        let written = try fields(of: record(snapshot(wearing: "work"), liveSlot: nil, aliveAt: polledAt))

        XCTAssertTrue(written["credential_service"] is NSNull)
        XCTAssertEqual(written["worn"] as? String, "work")
    }

    func testBeforeTheFirstPollAliveAtIsNull() throws {
        let written = try fields(of: record(snapshot(wearing: "work"), liveSlot: slot, aliveAt: nil))

        XCTAssertTrue(written["alive_at"] is NSNull)
    }

    func testHatsCoversALimitOnlyWithAutoSwitchOnAHatToGoToAndThatLimitsThresholdOn() {
        let cases: [(String, HatsSnapshot, SwitchCovers)] = [
            ("all on", snapshot(wearing: "work"), SwitchCovers(fiveHour: true, sevenDay: true)),
            ("5-hour threshold off", snapshot(wearing: "work", session: nil), SwitchCovers(fiveHour: false, sevenDay: true)),
            ("weekly threshold off", snapshot(wearing: "work", weekly: nil), SwitchCovers(fiveHour: true, sevenDay: false)),
            ("auto-switch off", snapshot(wearing: "work", autoSwitch: false), SwitchCovers(fiveHour: false, sevenDay: false)),
            ("no other hat", snapshot(wearing: "work", hats: ["work"]), SwitchCovers(fiveHour: false, sevenDay: false)),
        ]
        for (name, shown, expected) in cases {
            XCTAssertEqual(record(shown, liveSlot: slot, aliveAt: polledAt).switchCovers, expected, name)
        }
        XCTAssertNil(snapshot(wearing: "work", hats: ["work"]).nextInLine, "the case above has nowhere to go")
    }

    func testHatsCoversNoLimitWhenTheOnlyOtherHatIsOnVacation() {
        var shown = snapshot(wearing: "work")
        var away = hat("personal")
        away.vacationSince = now
        let back = SwitchCovers.create(from: shown)
        shown.rows = [
            HatRowState(hat: hat("work"), isWearing: true, usage: nil, usageTrouble: nil),
            HatRowState(hat: away, isWearing: false, usage: nil, usageTrouble: nil),
        ]

        XCTAssertEqual(back, SwitchCovers(fiveHour: true, sevenDay: true), "with the other hat back the switch covers both")
        XCTAssertEqual(SwitchCovers.create(from: shown), SwitchCovers(fiveHour: false, sevenDay: false))
    }

    func testEveryPollRewritesTheFileWithItsOwnTimeEvenWhenNothingElseChanged() throws {
        var file = HatUsageFile(url: folder.appendingPathComponent(HatUsageFile.name))
        let shown = snapshot(wearing: "work")
        XCTAssertEqual(file.setRecord(record(shown, liveSlot: slot, aliveAt: polledAt), at: now), .written)
        XCTAssertEqual(file.setRecord(record(shown, liveSlot: slot, aliveAt: polledAt), at: now), .unchanged,
                       "a redraw between two polls leaves the file alone")

        let next = polledAt.addingTimeInterval(300)
        XCTAssertEqual(file.setRecord(record(shown, liveSlot: slot, aliveAt: next), at: now), .written)

        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
        XCTAssertEqual(written["alive_at"] as? String, HatUsageRecord.getStamp(next))
    }

    func testEveryLandedPollStampsItsTimeAndKeepsTheCellOfTheWornHat() throws {
        let hats: AutoSwitchWatch.Hats = [("work", true), ("personal", false)]
        let watch = AutoSwitchWatch(wakes: NotificationCenter())
        watch.start(hats: { hats })
        defer { watch.stop() }
        XCTAssertNil(watch.lastPoll)
        var batch = UsagePollBatch()
        batch.liveSlot = slot

        watch.landed(batch, polled: hats, from: .timer)
        let first = try XCTUnwrap(watch.lastPoll)
        XCTAssertEqual(first.liveSlot, slot)
        watch.landed(UsagePollBatch(), polled: hats, from: .timer)

        let second = try XCTUnwrap(watch.lastPoll)
        XCTAssertGreaterThan(second.at, first.at, "a poll that read nothing new still says Hats runs")
        XCTAssertNil(second.liveSlot, "the cell comes from the latest poll")
    }

    func testAPollRecordsTheCellItReadTheWornHatFrom() {
        let slots = FakeSlots([:])

        let worn = AutoSwitchWatch.fetched([("personal", false), ("work", true)], world: slots.world(now: now, liveSlot: slot))
        let unknown = AutoSwitchWatch.fetched([("work", true)], world: slots.world(now: now, liveSlot: nil))
        let parkedOnly = AutoSwitchWatch.fetched([("personal", false)], world: slots.world(now: now, liveSlot: slot))

        XCTAssertEqual(worn.liveSlot, slot)
        XCTAssertNil(unknown.liveSlot)
        XCTAssertNil(parkedOnly.liveSlot, "with no hat worn there is no cell to name")
    }

    func testOnlyAPollWithAFreshReadingOfTheWornHatMovesAliveAtInTheFile() throws {
        let hats: AutoSwitchWatch.Hats = [("work", true), ("personal", false)]
        let shown = snapshot(wearing: "work")
        let watch = AutoSwitchWatch(wakes: NotificationCenter())
        var file = HatUsageFile(url: folder.appendingPathComponent(HatUsageFile.name))
        var stamps: [String] = []
        watch.onReadings = { _ in
            _ = file.setRecord(HatUsageRecord.create(from: shown, watch: watch, stages: []), at: self.now)
            let written = try? JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any]
            stamps.append((written?["alive_at"] as? String) ?? "null")
        }
        watch.start(hats: { hats })
        defer { watch.stop() }
        var fresh = UsagePollBatch()
        fresh.liveSlot = slot
        fresh.readings = ["work": UsageReading(session: nil, weekly: nil)]
        var parkedOnly = UsagePollBatch()
        parkedOnly.liveSlot = slot
        parkedOnly.readings = ["personal": UsageReading(session: nil, weekly: nil)]

        watch.landed(parkedOnly, polled: hats, from: .timer)
        watch.landed(fresh, polled: hats, from: .timer)
        Thread.sleep(forTimeInterval: 1.1)
        watch.landed(parkedOnly, polled: hats, from: .timer)
        watch.landed(UsagePollBatch(), polled: hats, from: .timer)
        Thread.sleep(forTimeInterval: 1.1)
        watch.landed(fresh, polled: hats, from: .timer)

        XCTAssertEqual(stamps.count, 5)
        XCTAssertEqual(stamps[0], "null", "no fresh reading of the worn hat yet: \(stamps)")
        XCTAssertNotEqual(stamps[1], "null")
        XCTAssertEqual(stamps[2], stamps[1], "a poll that read only a parked hat keeps alive_at")
        XCTAssertEqual(stamps[3], stamps[1], "a poll that read nothing keeps alive_at")
        XCTAssertNotEqual(stamps[4], stamps[1], "the next fresh reading of the worn hat moves it")
        XCTAssertEqual(stamps[4], watch.aliveAt.map(HatUsageRecord.getStamp))
    }

    func testAWakeOfTheMacPollsOnceTheNetworkHadTimeToComeUp() {
        let hats: AutoSwitchWatch.Hats = [("work", true)]
        let wakes = NotificationCenter()
        let watch = AutoSwitchWatch(wakes: wakes)
        let slots = FakeSlots([:])
        watch.makeWorld = { _ in slots.world(now: self.now, liveSlot: nil) }
        watch.wakeDelay = 0.6
        var landedAt: Date?
        let landed = expectation(description: "a poll landed")
        landed.assertForOverFulfill = false
        watch.onReadings = { _ in
            landedAt = landedAt ?? Date()
            landed.fulfill()
        }
        watch.start(hats: { hats })
        defer { watch.stop() }
        let woke = Date()

        wakes.post(name: NSWorkspace.didWakeNotification, object: nil)

        wait(for: [landed], timeout: 1.5)
        XCTAssertGreaterThanOrEqual(landedAt?.timeIntervalSince(woke) ?? 0, 0.6,
                                    "measured 2026-11-15: a poll 4 s after the wake found no network and "
                                        + "every hat showed \"latest check failed\" until the next poll")
        XCTAssertEqual(AutoSwitchWatch(wakes: NotificationCenter()).wakeDelay, 25,
                       "the network was answering within two minutes of that wake; 25 s is chosen, not measured")
    }

    private func countLandingsAfterWakes(_ act: (AutoSwitchWatch, NotificationCenter) -> Void) -> Int {
        let hats: AutoSwitchWatch.Hats = [("work", true)]
        let wakes = NotificationCenter()
        let watch = AutoSwitchWatch(wakes: wakes)
        let slots = FakeSlots([:])
        watch.makeWorld = { _ in slots.world(now: self.now, liveSlot: nil) }
        watch.wakeDelay = 0.3
        var landings = 0
        watch.onReadings = { _ in landings += 1 }
        watch.start(hats: { hats })
        defer { watch.stop() }
        act(watch, wakes)
        let quiet = expectation(description: "the first timer poll is two seconds away")
        quiet.isInverted = true
        wait(for: [quiet], timeout: 1.2)

        return landings
    }

    func testTwoWakesInsideTheDelayGiveOnePoll() {
        let landings = countLandingsAfterWakes { _, wakes in
            wakes.post(name: NSWorkspace.didWakeNotification, object: nil)
            wakes.post(name: NSWorkspace.didWakeNotification, object: nil)
        }

        XCTAssertEqual(landings, 1, "the second wake replaces the poll the first one scheduled")
    }

    func testARestartInsideTheDelayDropsThePollTheOldWakeScheduled() {
        let landings = countLandingsAfterWakes { watch, wakes in
            wakes.post(name: NSWorkspace.didWakeNotification, object: nil)
            watch.stop()
            watch.start(hats: { [("personal", true)] })
        }

        XCTAssertEqual(landings, 0, "stop cancels the waiting wake poll, so no poll runs with the old hats")
    }
}
