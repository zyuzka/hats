import XCTest
@testable import Hats

final class ContextChannelWiringTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("channel-wiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func createChannel() -> ContextThresholdsChannel {
        ContextThresholdsChannel(
            root: root,
            launchedAt: Date(),
            notify: { _ in },
            pollEvery: 0.3,
            log: { _, _ in }
        )
    }

    private func snapshot(wearing: String) -> HatsSnapshot {
        let reading = UsageReading(
            session: UsageWindow(used: 81, limit: 100, resetsAt: SessionStageLimitWaitingTests.stamp("2026-11-14T15:00:00Z")),
            weekly: UsageWindow(used: 82, limit: 100, resetsAt: SessionStageLimitWaitingTests.stamp("2026-11-18T09:00:00Z"))
        )
        var snapshot = HatsSnapshot()
        snapshot.rows = ["work", "personal"].map { id in
            var hat = Account(id: id, email: "\(id)@company.com", browser: nil)
            hat.name = id.capitalized
            hat.hasStoredCredentials = true
            return HatRowState(hat: hat, isWearing: id == wearing, usage: reading, usageTrouble: nil)
        }

        return snapshot
    }

    func testALimitNoticeNamesTheHatByItsTitle() {
        let channel = createChannel()
        var shown: HatsSnapshot? = snapshot(wearing: "work")

        channel.setWiring(snapshot: { shown }, stagesRead: {})

        XCTAssertEqual(channel.hatTitle("work"), "Work",
                       "without this the notice title shows the hat's internal id")
        XCTAssertEqual(channel.hatTitle("gone"), "gone", "a hat the menu no longer has keeps its id")
        shown = nil
        XCTAssertEqual(channel.hatTitle("work"), "work", "and with no menu yet the id is all there is")
    }

    func testAStageReadWithAWarningWritesTheFirstWarningIntoTheHatUsageFile() throws {
        let channel = createChannel()
        let shown = snapshot(wearing: "work")
        let watch = AutoSwitchWatch(wakes: NotificationCenter())
        var file = HatUsageFile(url: root.appendingPathComponent(HatUsageFile.name))
        let folder = root.appendingPathComponent(WindowThresholdsFile.stageFolderName)
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        var fields = try XCTUnwrap(
            JSONSerialization.jsonObject(with: SessionStageLimitWaitingTests.loadTheSharedSample()) as? [String: Any]
        )
        fields["at"] = ISO8601DateFormatter().string(from: Date())
        let session = try XCTUnwrap(fields["session"] as? String)
        try JSONSerialization.data(withJSONObject: fields).write(to: folder.appendingPathComponent(session + ".json"))
        let written = expectation(description: "the stage read wrote the file")
        var isWritten = false
        channel.setWiring(snapshot: { shown }, stagesRead: {
            guard !isWritten, case .written = file.setRecord(from: shown, watch: watch, channel: channel, at: Date())
            else { return }
            isWritten = true
            written.fulfill()
        })

        channel.start { [] }
        defer { channel.stop() }

        wait(for: [written], timeout: 5)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any]
        let warned = try XCTUnwrap(saved?["first_warned"] as? [String: Any])
        XCTAssertEqual(warned["five_hour"] as? [String: String], [
            "episode": "2026-11-14T15:00:00Z",
            "at": "2026-11-14T14:10:00.000Z",
        ], "the stages the channel read are the ones the file is written from")
    }
}
