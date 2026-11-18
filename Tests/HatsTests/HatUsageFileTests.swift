import XCTest
@testable import Hats

final class HatUsageFileTests: XCTestCase {
    private var folder: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let readAt = Date(timeIntervalSince1970: 1_799_999_000)
    private let resets = Date(timeIntervalSince1970: 1_800_010_000)
    private let polledAt = Date(timeIntervalSince1970: 1_799_999_500)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("hat-usage-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func hat(_ id: String, switchable: Bool = true) -> Account {
        var hat = Account(id: id, email: "\(id)@company.com", browser: nil)
        hat.hasStoredCredentials = switchable
        if switchable { hat.identity = CLIIdentity(oauthAccount: [:], userID: nil) }
        return hat
    }

    private func snapshot(
        wearing: String?,
        hats: [Account],
        reading: UsageReading? = nil,
        autoSwitch: Bool = true
    ) -> HatsSnapshot {
        var snapshot = HatsSnapshot()
        snapshot.rows = hats.map {
            HatRowState(hat: $0, isWearing: $0.id == wearing, usage: $0.id == wearing ? reading : nil, usageTrouble: nil)
        }
        snapshot.settings.autoSwitch.isOn = autoSwitch
        return snapshot
    }

    private var reading: UsageReading {
        UsageReading(
            session: UsageWindow(used: 62, limit: 100, resetsAt: resets),
            weekly: UsageWindow(used: 30, limit: 100, resetsAt: nil)
        )
    }

    private func written(_ file: HatUsageFile) throws -> [String: Any] {
        let data = try Data(contentsOf: file.url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheWornHatIsWrittenWithItsReadingAndTheTimeOfThatReading() throws {
        var file = HatUsageFile(url: folder.appendingPathComponent(HatUsageFile.name))
        let record = HatUsageRecord.create(
            from: snapshot(wearing: "work", hats: [hat("work"), hat("personal")], reading: reading),
            readAt: ["work": readAt, "personal": now],
            liveSlot: FakeSlots.live,
            aliveAt: polledAt,
            stages: []
        )

        XCTAssertEqual(file.setRecord(record, at: now), .written)

        let fields = try written(file)
        XCTAssertEqual(fields["worn"] as? String, "work")
        XCTAssertEqual((fields["five_hour"] as? [String: Any])?["percent"] as? Int, 62)
        XCTAssertEqual((fields["five_hour"] as? [String: Any])?["resets_at"] as? String, HatUsageRecord.getStamp(resets))
        XCTAssertEqual((fields["weekly"] as? [String: Any])?["percent"] as? Int, 30)
        XCTAssertTrue((fields["weekly"] as? [String: Any])?["resets_at"] is NSNull)
        XCTAssertEqual(fields["measured_at"] as? String, HatUsageRecord.getStamp(readAt),
                       "the time of the worn hat's reading, not of the redraw")
        XCTAssertEqual(fields["has_a_hat_to_switch_to"] as? Bool, true)
        XCTAssertEqual(fields["auto_switch_on"] as? Bool, true)
        XCTAssertEqual(fields["written_at"] as? String, HatUsageRecord.getStamp(now))
        XCTAssertEqual(
            Set(fields.keys),
            [
                "worn",
                "five_hour",
                "weekly",
                "measured_at",
                "has_a_hat_to_switch_to",
                "auto_switch_on",
                "written_at",
                "credential_service",
                "switch_covers",
                "alive_at",
                "first_warned",
            ]
        )
        let text = try String(contentsOf: file.url, encoding: .utf8)
        XCTAssertFalse(text.contains("@"), "no address in the file another program reads")
    }

    func testAHatWithoutAReadingAndNoHatAtAllLeaveTheirFieldsNull() throws {
        var file = HatUsageFile(url: folder.appendingPathComponent(HatUsageFile.name))
        let unread = HatUsageRecord.create(
            from: snapshot(wearing: "work", hats: [hat("work"), hat("personal")]),
            readAt: ["work": readAt],
            liveSlot: FakeSlots.live,
            aliveAt: polledAt,
            stages: []
        )
        XCTAssertEqual(file.setRecord(unread, at: now), .written)
        var fields = try written(file)
        XCTAssertEqual(fields["worn"] as? String, "work")
        XCTAssertTrue(fields["five_hour"] is NSNull)
        XCTAssertTrue(fields["weekly"] is NSNull)
        XCTAssertTrue(fields["measured_at"] is NSNull, "a stamp without a reading measures nothing")

        let bare = HatUsageRecord.create(
            from: snapshot(wearing: nil, hats: [hat("work"), hat("personal")], autoSwitch: false),
            readAt: [:],
            liveSlot: FakeSlots.live,
            aliveAt: polledAt,
            stages: []
        )
        XCTAssertEqual(file.setRecord(bare, at: now), .written)
        fields = try written(file)
        XCTAssertTrue(fields["worn"] is NSNull)
        XCTAssertEqual(fields["has_a_hat_to_switch_to"] as? Bool, true, "decided by nextInLine, as for auto-switch")
        XCTAssertEqual(fields["auto_switch_on"] as? Bool, false, "the toggle is written apart: nextInLine ignores it")
    }

    func testNowhereToSwitchToFollowsTheAutoSwitchChoice() {
        let alone = HatUsageRecord.create(
            from: snapshot(wearing: "work", hats: [hat("work"), hat("team", switchable: false)], reading: reading),
            readAt: [:],
            liveSlot: FakeSlots.live,
            aliveAt: polledAt,
            stages: []
        )
        XCTAssertFalse(alone.hasAHatToSwitchTo)
        let shown = snapshot(wearing: "work", hats: [hat("work"), hat("team", switchable: false)], reading: reading)
        XCTAssertEqual(alone.hasAHatToSwitchTo, shown.nextInLine != nil)
    }

    func testTheFileIsRewrittenOnlyWhenTheRecordChanges() throws {
        var file = HatUsageFile(url: folder.appendingPathComponent(HatUsageFile.name))
        let hats = [hat("work"), hat("personal")]
        let first = HatUsageRecord.create(
            from: snapshot(wearing: "work", hats: hats, reading: reading),
            readAt: ["work": readAt],
            liveSlot: FakeSlots.live,
            aliveAt: polledAt,
            stages: []
        )
        XCTAssertEqual(file.setRecord(first, at: now), .written)
        let inode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.systemFileNumber] as? Int

        XCTAssertEqual(file.setRecord(first, at: now.addingTimeInterval(300)), .unchanged,
                       "a redraw with no new reading and no other hat leaves the file alone")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.url.path)[.systemFileNumber] as? Int, inode)
        XCTAssertEqual(try written(file)["written_at"] as? String, HatUsageRecord.getStamp(now))

        let other = HatUsageRecord.create(
            from: snapshot(wearing: "personal", hats: hats),
            readAt: ["work": readAt],
            liveSlot: FakeSlots.live,
            aliveAt: polledAt,
            stages: []
        )
        XCTAssertEqual(file.setRecord(other, at: now.addingTimeInterval(600)), .written, "another hat put on is written")
        XCTAssertEqual(try written(file)["worn"] as? String, "personal")

        let polled = HatUsageRecord.create(
            from: snapshot(wearing: "personal", hats: hats, reading: reading),
            readAt: ["personal": now],
            liveSlot: FakeSlots.live,
            aliveAt: polledAt,
            stages: []
        )
        XCTAssertEqual(file.setRecord(polled, at: now.addingTimeInterval(900)), .written, "a new reading is written")
    }

    func testADeletedFileIsWrittenAgainEvenWhenTheRecordIsTheSame() throws {
        var file = HatUsageFile(url: folder.appendingPathComponent(HatUsageFile.name))
        let record = HatUsageRecord.create(
            from: snapshot(wearing: "work", hats: [hat("work"), hat("personal")], reading: reading),
            readAt: ["work": readAt],
            liveSlot: FakeSlots.live,
            aliveAt: polledAt,
            stages: []
        )
        XCTAssertEqual(file.setRecord(record, at: now), .written)
        try FileManager.default.removeItem(at: file.url)

        XCTAssertEqual(file.setRecord(record, at: now.addingTimeInterval(60)), .written)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        XCTAssertEqual(file.setRecord(record, at: now.addingTimeInterval(120)), .unchanged)
    }

    func testAFailedWriteIsReportedAndRetriedNextTime() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("blocked"))
        var file = HatUsageFile(url: folder.appendingPathComponent("blocked/\(HatUsageFile.name)"))
        let record = HatUsageRecord.create(
            from: snapshot(wearing: nil, hats: []),
            readAt: [:],
            liveSlot: FakeSlots.live,
            aliveAt: polledAt,
            stages: []
        )

        guard case .failed = file.setRecord(record, at: now) else { return XCTFail("a folder that is a file must fail") }
        guard case .failed = file.setRecord(record, at: now) else {
            return XCTFail("nothing was written, so the same record is tried again rather than called unchanged")
        }
    }

    func testTheDefaultFileLivesInTheStateFolder() {
        XCTAssertEqual(HatUsageFile().url, StateDirectory.url.appendingPathComponent("hat-usage.json"))
    }
}
