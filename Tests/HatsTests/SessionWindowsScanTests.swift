import Darwin
import XCTest
@testable import Hats

final class SessionWindowsScanTests: XCTestCase {
    private var folder: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var lines: [(String, [String: String])] = []
    private var reads: [String] = []

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-windows-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        lines = []
        reads = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func scanner() -> SessionWindowsScan {
        SessionWindowsScan(
            read: { [unowned self] name, folder in
                reads.append(name)
                return SessionWindowFile.getRecord(name, in: folder)
            },
            log: { [unowned self] event, details in lines.append((event, details)) }
        )
    }

    private func stamp(_ secondsAgo: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(-secondsAgo))
    }

    private func put(
        _ session: String,
        tokens: Int? = 449_659,
        state: String = "read",
        secondsAgo: TimeInterval = 60,
        modified: Date? = nil
    ) throws {
        let window: Any = tokens == nil ? NSNull() : 1_000_000
        let percent: Any = tokens.map { SessionWindow.getPercent(tokens: $0, window: 1_000_000) } ?? NSNull()
        let fields: [String: Any] = [
            "session": session,
            "tokens": tokens ?? NSNull(),
            "window": window,
            "percent": percent,
            "state": state,
            "measured_at": stamp(secondsAgo),
        ]
        try place(try JSONSerialization.data(withJSONObject: fields), as: "\(session).json", modified: modified)
    }

    private func place(_ data: Data, as name: String, modified: Date? = nil) throws {
        let staged = folder.appendingPathComponent(".tmp-\(UUID().uuidString)")
        try data.write(to: staged)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: staged.path)
        }
        XCTAssertEqual(rename(staged.path, folder.appendingPathComponent(name).path), 0, "the record is put in place whole")
    }

    private func events(_ name: String) -> [[String: String]] {
        lines.filter { $0.0 == name }.map(\.1)
    }

    func testServiceFilesAreNotReadAndRecordsAreReturnedBySession() throws {
        try put("b-session")
        try put("a-session")
        try Data("{}".utf8).write(to: folder.appendingPathComponent(".tmp-abc.json"))
        try Data().write(to: folder.appendingPathComponent(".lock"))
        try Data("x".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        var scan = scanner()

        let windows = scan.findWindows(in: folder, now: now)

        XCTAssertEqual(windows.map(\.session), ["a-session", "b-session"])
        XCTAssertEqual(Set(reads), ["a-session.json", "b-session.json"], ".tmp-*, .lock and other files are not read")
    }

    func testOnlyAFileWithANewStampIsReadAgain() throws {
        try put("a-session")
        try put("b-session")
        var scan = scanner()
        _ = scan.findWindows(in: folder, now: now)
        reads = []

        _ = scan.findWindows(in: folder, now: now)
        XCTAssertEqual(reads, [], "nothing changed, nothing is read")

        try put("b-session", tokens: 520_000)
        let windows = scan.findWindows(in: folder, now: now)
        XCTAssertEqual(reads, ["b-session.json"])
        XCTAssertEqual(windows.first { $0.session == "b-session" }?.percent, 52)

        try FileManager.default.removeItem(at: folder.appendingPathComponent("a-session.json"))
        XCTAssertEqual(scan.findWindows(in: folder, now: now).map(\.session), ["b-session"], "a removed file is gone")
    }

    func testAtMost500FilesAreReadAndTheNewestAreTheOnesKept() throws {
        let older = now.addingTimeInterval(-7200)
        for index in 0..<SessionWindowsScan.fileLimit {
            try put("s-\(index)", modified: older)
        }
        try put("newest-one", modified: now)
        try put("newest-two", modified: now.addingTimeInterval(-1))
        var scan = scanner()

        let windows = scan.findWindows(in: folder, now: now)

        XCTAssertEqual(reads.count, SessionWindowsScan.fileLimit)
        XCTAssertEqual(windows.count, SessionWindowsScan.fileLimit)
        XCTAssertTrue(windows.contains { $0.session == "newest-one" }, "the newest file is never the one left out")
        XCTAssertTrue(windows.contains { $0.session == "newest-two" })
    }

    func testTheFirstReadLeavesOneSummaryLineAndASkippedFileOneLinePerRun() throws {
        try put("a-session")
        try put("old-session", secondsAgo: 7200)
        try place(Data("not json".utf8), as: "broken.json")
        var scan = scanner()

        _ = scan.findWindows(in: folder, now: now)

        XCTAssertEqual(events("sessionWindows.read").count, 1)
        XCTAssertEqual(
            events("sessionWindows.read").first,
            ["files": "3", "readable": "2", "skipped": "1", "recent": "1"]
        )
        XCTAssertEqual(events("sessionWindows.skipped").map { $0["name"] }, ["broken.json"])
        XCTAssertEqual(events("sessionWindows.changed").count, 0, "the first read is summed up, not listed")

        try place(Data("still not json".utf8), as: "broken.json")
        _ = scan.findWindows(in: folder, now: now)
        XCTAssertEqual(events("sessionWindows.skipped").count, 1, "one line per name per run, even when re-read")
    }

    func testNoMoreThanTwentyNamesAreToldAsSkipped() throws {
        for index in 0..<25 {
            try place(Data("x".utf8), as: "broken-\(index).json")
        }
        var scan = scanner()

        _ = scan.findWindows(in: folder, now: now)

        XCTAssertEqual(events("sessionWindows.skipped").count, SessionWindowsScan.skippedNameLimit)
    }

    func testARecentSessionIsToldWhenItsStateOrItsTenOfPercentChanges() throws {
        try put("a-session", tokens: 450_000)
        try put("old-session", tokens: 450_000, secondsAgo: 7200)
        var scan = scanner()
        _ = scan.findWindows(in: folder, now: now)

        try put("a-session", tokens: 470_000)
        _ = scan.findWindows(in: folder, now: now)
        XCTAssertEqual(events("sessionWindows.changed").count, 0, "45% to 47% stays in the same ten")

        try put("a-session", tokens: 520_000)
        _ = scan.findWindows(in: folder, now: now)
        XCTAssertEqual(
            events("sessionWindows.changed").last,
            ["session": "a-sessio", "state": "read", "percent": "52", "tokens": "520000"]
        )

        try put("a-session", tokens: nil, state: "compacted")
        _ = scan.findWindows(in: folder, now: now)
        XCTAssertEqual(events("sessionWindows.changed").last, ["session": "a-sessio", "state": "compacted"])

        try put("old-session", tokens: 900_000, secondsAgo: 7000)
        _ = scan.findWindows(in: folder, now: now)
        XCTAssertEqual(events("sessionWindows.changed").count, 2, "a session not measured in the last hour is not told")

        try put("new-session", tokens: 100_000)
        _ = scan.findWindows(in: folder, now: now)
        XCTAssertEqual(events("sessionWindows.changed").last?["session"], "new-sess", "a session seen first after the first read")
    }

    func testAFolderThatIsALinkIsNotListed() throws {
        try put("a-session")
        let link = folder.deletingLastPathComponent().appendingPathComponent("link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        defer { try? FileManager.default.removeItem(at: link) }
        var scan = scanner()

        XCTAssertEqual(scan.findWindows(in: link, now: now), [])
        XCTAssertEqual(reads, [])
    }
}
