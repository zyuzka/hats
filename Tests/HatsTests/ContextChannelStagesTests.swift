import XCTest
@testable import Hats

final class ContextChannelStagesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("channel-stages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testTheChannelKeepsTheLastStagesItReadAndSaysSo() throws {
        let channel = ContextThresholdsChannel(root: root, launchedAt: Date(), notify: { _ in }, pollEvery: 0.3, log: { _, _ in })
        let folder = root.appendingPathComponent(WindowThresholdsFile.stageFolderName)
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        var fields = try XCTUnwrap(
            JSONSerialization.jsonObject(with: SessionStageLimitWaitingTests.loadTheSharedSample()) as? [String: Any]
        )
        fields["at"] = ISO8601DateFormatter().string(from: Date())
        let session = try XCTUnwrap(fields["session"] as? String)
        try JSONSerialization.data(withJSONObject: fields).write(to: folder.appendingPathComponent(session + ".json"))
        let seen = expectation(description: "a read with the sample's session is told")
        var isSeen = false
        channel.onStagesRead = { [unowned channel] in
            guard !isSeen, channel.lastStages.map(\.session) == [session] else { return }
            isSeen = true
            seen.fulfill()
        }

        channel.start { [] }
        defer { channel.stop() }

        wait(for: [seen], timeout: 5)
        XCTAssertEqual(channel.lastStages.first?.limitEpisodes.count, 2)
    }
}
