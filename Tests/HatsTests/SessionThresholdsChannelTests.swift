import Darwin
import UserNotifications
import XCTest
@testable import Hats

final class SessionThresholdsChannelTests: XCTestCase {
    private var root: URL!
    private var folder: URL { root.appendingPathComponent(WindowThresholdsFile.stageFolderName) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("session-thresholds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        chmod(folder.path, 0o700)
        try? FileManager.default.removeItem(at: root)
    }

    private func createRecord(_ changes: [String: Any], session: String = "5a32129e-d019") throws -> Data {
        var fields = SessionStageFileTests.fields(changes)
        fields["session"] = session
        fields["at"] = ISO8601DateFormatter().string(from: Date())

        return try JSONSerialization.data(withJSONObject: fields)
    }

    private func place(_ changes: [String: Any], session: String = "5a32129e-d019") throws {
        let staged = folder.appendingPathComponent(".tmp-\(session)")
        try createRecord(changes, session: session).write(to: staged)
        XCTAssertEqual(rename(staged.path, folder.appendingPathComponent("\(session).json").path), 0)
    }

    private func overwriteInPlace(_ data: Data, session: String) throws {
        let handle = try FileHandle(forWritingTo: folder.appendingPathComponent("\(session).json"))
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
    }

    private func placeOld(_ count: Int, daysAgo: Double) throws {
        let at = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-daysAgo * 86400))
        for index in 0..<count {
            let session = "old-\(index)"
            var fields = SessionStageFileTests.fields(["at": at])
            fields["session"] = session
            try JSONSerialization.data(withJSONObject: fields).write(to: folder.appendingPathComponent("\(session).json"))
        }
    }

    private func countFiles() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }.count
    }

    func testTheRealWatchSignalsItsFirstReadOfAnEmptyFolderAndSeesTheSameFileRewrittenInPlace() throws {
        var told: [UNMutableNotificationContent] = []
        let notices = ContextThresholdNotices(notify: { told.append($0) })
        let watch = SessionThresholds(folder: folder, pollEvery: 0.3, log: { _, _ in })
        let firstRead = expectation(description: "the first read of the empty folder is signalled")
        let toldAt = (1...3).map { expectation(description: "notice \($0)") }
        var reads: [SessionStagesRead] = []
        watch.onRead = { found in
            reads.append(found)
            let before = told.count
            notices.noteARead(found, windows: [])
            if reads.count == 1 { firstRead.fulfill() }
            if told.count > before { toldAt[told.count - 1].fulfill() }
        }

        watch.start()
        defer { watch.stop() }
        wait(for: [firstRead], timeout: 5)
        XCTAssertEqual(reads.first?.stages, [], "an empty first read is still a read")
        try place(["stage": "requested", "warn_round": 1, "save_round": 1])
        wait(for: [toldAt[0]], timeout: 5)
        try overwriteInPlace(createRecord(["stage": "requested", "warn_round": 1, "save_round": 2]), session: "5a32129e-d019")
        wait(for: [toldAt[1]], timeout: 5)
        try overwriteInPlace(createRecord(["stage": "warned", "warn_round": 2, "save_round": 2, "percent": 47]),
                             session: "5a32129e-d019")

        wait(for: [toldAt[2]], timeout: 5)
        XCTAssertEqual(told.map(\.body), [
            HatsCopy.getAnchorNoticeBody(save: 55, drainMinutes: nil),
            HatsCopy.getAnchorNoticeBody(save: 55, drainMinutes: nil),
            HatsCopy.getWarnNoticeBody(warn: 45, save: 55),
        ], "the mod rewrites its file in place, which a folder watch alone does not see")
    }

    func testTheChannelTellsNewRoundsOnlyAndRemembersARoundThroughAnUnreadableWrite() throws {
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place(["stage": "requested", "warn_round": 1, "save_round": 1])
        try Data("{".utf8).write(to: folder.appendingPathComponent("broken.json"))
        try setFileTime(Date().addingTimeInterval(-60), of: "broken.json")
        var told: [String] = []
        let firstRead = expectation(description: "the first read is done: the broken file, read last as the oldest, was skipped")
        let halfWritten = expectation(description: "the half-written record was skipped")
        let second = expectation(description: "the next anchor round is told")
        let speaker = expectation(description: "another session's request is told")
        let channel = ContextThresholdsChannel(
            root: root,
            launchedAt: Date(),
            notify: { content in
                told.append(content.title)
                if told.count == 1 { second.fulfill() }
                if told.count == 2 { speaker.fulfill() }
            },
            pollEvery: 0.3,
            log: { event, details in
                guard event == "sessionThresholds.skipped" else { return }
                switch details["name"] {
                case "broken.json": firstRead.fulfill()
                case "5a32129e-d019.json": halfWritten.fulfill()
                default: break
                }
            }
        )

        channel.start { [] }
        defer { channel.stop() }
        wait(for: [firstRead], timeout: 5)
        try place(["stage": "requested", "warn_round": 1, "save_round": 2, "percent": 58])
        wait(for: [second], timeout: 5)
        try overwriteInPlace(Data(#"{"session": "5a32129e-d019", "sta"#.utf8), session: "5a32129e-d019")
        wait(for: [halfWritten], timeout: 5)
        try overwriteInPlace(createRecord(["stage": "requested", "warn_round": 1, "save_round": 2, "percent": 58]),
                             session: "5a32129e-d019")
        try place(["stage": "requested", "warn_round": 1, "save_round": 1, "percent": 61], session: "other")

        wait(for: [speaker], timeout: 5)
        XCTAssertEqual(told, [
            HatsCopy.getContextNoticeTitle(label: "hats", percent: 58),
            HatsCopy.getContextNoticeTitle(label: "hats", percent: 61),
        ], "the record already there at start is not told, and round 2 is not told again after the bad write")
    }

    func testRecordsOlderThan30DaysAreSweptAtMost200AtATime() throws {
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try placeOld(1000, daysAgo: 31)
        try place(["stage": "saved"], session: "fresh")
        var scan = SessionThresholdsScan(log: { _, _ in })

        let first = try XCTUnwrap(scan.findStages(in: folder, now: Date())).stages
        XCTAssertEqual(try countFiles(), 801, "500 newest read, 200 of the old ones swept")
        XCTAssertEqual(first.count, 300)
        XCTAssertTrue(first.contains { $0.session == "fresh" })
        XCTAssertTrue(first.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent("\($0.session).json").path) },
                      "a swept record is not handed on")
        _ = scan.findStages(in: folder, now: Date())

        XCTAssertEqual(try countFiles(), 601)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("fresh.json").path))
    }

    func testTheSweepGoesByAtAndNotByTheFileTime() throws {
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place(["stage": "saved"], session: "touched-long-ago")
        let longAgo = Date().addingTimeInterval(-40 * 86400)
        try FileManager.default.setAttributes(
            [.modificationDate: longAgo],
            ofItemAtPath: folder.appendingPathComponent("touched-long-ago.json").path
        )
        try placeOld(1, daysAgo: 31)
        var scan = SessionThresholdsScan(log: { _, _ in })

        let found = try XCTUnwrap(scan.findStages(in: folder, now: Date())).stages

        XCTAssertEqual(found.map(\.session), ["touched-long-ago"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["touched-long-ago.json"])
    }

    func testTheSweepRunsOnTheWatchQueueAndAFailedRemovalIsJournaledOnce() throws {
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try placeOld(2, daysAgo: 31)
        XCTAssertEqual(chmod(folder.path, 0o500), 0)
        let lock = NSLock()
        var lines: [(name: String, onMain: Bool)] = []
        let journaled = expectation(description: "the failed removal is journaled from the sweep")
        journaled.assertForOverFulfill = false
        let firstRead = expectation(description: "the first read")
        let thirdRead = expectation(description: "two more reads after it")
        var reads = 0
        let watch = SessionThresholds(folder: folder, pollEvery: 0.2, log: { event, details in
            guard event == "sessionThresholds.notSwept" else { return }
            lock.lock()
            lines.append((details["name"] ?? "", Thread.isMainThread))
            lock.unlock()
            journaled.fulfill()
        })
        watch.onRead = { found in
            reads += 1
            if reads == 1 {
                XCTAssertEqual(found.stages.count, 2, "a record that could not be removed is still handed on")
                firstRead.fulfill()
            }
            if reads == 3 { thirdRead.fulfill() }
        }

        watch.start()
        defer { watch.stop() }

        wait(for: [journaled, firstRead, thirdRead], timeout: 5)
        lock.lock()
        defer { lock.unlock() }
        XCTAssertEqual(lines.map(\.name), ["old-0.json"], "the same reason is told once, not on every read")
        XCTAssertEqual(lines.first?.onMain, false, "the sweep runs on the watch's queue, not on the main thread")
        XCTAssertEqual(try countFiles(), 2)
    }

    func testAFolderThatCannotBeListedIsNoReadAndNotEmpty() throws {
        var lines: [String] = []
        var scan = SessionThresholdsScan(log: { event, _ in lines.append(event) })
        XCTAssertNil(scan.findStages(in: folder, now: Date()), "no folder at all")
        try Data("x".utf8).write(to: folder)
        XCTAssertNil(scan.findStages(in: folder, now: Date()), "a file where the folder should be")
        try FileManager.default.removeItem(at: folder)
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        XCTAssertEqual(chmod(folder.path, 0o300), 0)
        XCTAssertNil(scan.findStages(in: folder, now: Date()), "a folder that cannot be listed")
        XCTAssertEqual(chmod(folder.path, 0o700), 0)

        XCTAssertEqual(scan.findStages(in: folder, now: Date()), SessionStagesRead(stages: [], listed: []),
                       "an empty folder is a read with nothing in it")
        XCTAssertEqual(lines, ["sessionThresholds.unlisted"], "one line until a listing succeeds")
        XCTAssertNil(scan.findStages(in: root.appendingPathComponent("gone"), now: Date()))
        XCTAssertEqual(lines.count, 2, "after a success the trouble is told again")
    }

    func testAFirstListingThatFailsIsNotTheBaselineSoWhatLayThereIsNotToldLater() throws {
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place(["stage": "requested", "warn_round": 1, "save_round": 1, "percent": 56])
        let lock = NSLock()
        var failures = 2
        var told: [String] = []
        var reads: [SessionStagesRead] = []
        let notices = ContextThresholdNotices(notify: { told.append($0.title) })
        let watch = SessionThresholds(
            folder: folder,
            pollEvery: 0.2,
            list: { url in
                lock.lock()
                defer { lock.unlock() }
                guard failures == 0 else {
                    failures -= 1
                    return nil
                }
                return SessionWindowsScan.findCandidates(in: url)
            },
            log: { _, _ in }
        )
        let firstRead = expectation(description: "the first listing that succeeds is the first read")
        let toldNew = expectation(description: "the round written after it is told")
        toldNew.assertForOverFulfill = false
        watch.onRead = { found in
            reads.append(found)
            notices.noteARead(found, windows: [])
            if reads.count == 1 { firstRead.fulfill() }
            if told.count == 1 { toldNew.fulfill() }
        }

        watch.start()
        defer { watch.stop() }
        wait(for: [firstRead], timeout: 5)
        XCTAssertEqual(reads.first?.stages.map(\.saveRound), [1], "the failed listings handed nothing on, not an empty list")
        try place(["stage": "requested", "warn_round": 1, "save_round": 2, "percent": 58])

        wait(for: [toldNew], timeout: 5)
        XCTAssertEqual(told, [HatsCopy.getContextNoticeTitle(label: "hats", percent: 58)],
                       "the record that lay there before the first read is not told")
    }

    private func setFileTime(_ date: Date, of name: String) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: folder.appendingPathComponent(name).path)
    }

    func testOldFilesBeyondTheReadLimitAreSweptByTheirFileTime() throws {
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try placeOld(30, daysAgo: 40)
        for index in 0..<30 { try setFileTime(Date().addingTimeInterval(-40 * 86400), of: "old-\(index).json") }
        for index in 0..<SessionWindowsScan.fileLimit + 1 { try place(["stage": "saved"], session: "fresh-\(index)") }
        var scan = SessionThresholdsScan(log: { _, _ in })

        let found = try XCTUnwrap(scan.findStages(in: folder, now: Date()))

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertFalse(names.contains { $0.hasPrefix("old-") }, "past the 500 newest, an old file goes by its file time")
        XCTAssertEqual(names.count, SessionWindowsScan.fileLimit + 1)
        XCTAssertEqual(found.stages.count, SessionWindowsScan.fileLimit, "only the 500 newest are read")
        XCTAssertEqual(found.listed.count, SessionWindowsScan.fileLimit + 1, "the one past the limit is still listed")
        XCTAssertFalse(found.listed.contains("old-0"), "a swept file is not")
    }

    func testAnOldFileThatNeverReadsIsSweptByItsFileTime() throws {
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try Data("{".utf8).write(to: folder.appendingPathComponent("broken-old.json"))
        try setFileTime(Date().addingTimeInterval(-40 * 86400), of: "broken-old.json")
        try Data("{".utf8).write(to: folder.appendingPathComponent("broken-new.json"))
        try place(["stage": "saved"], session: "fresh")
        var scan = SessionThresholdsScan(log: { _, _ in })

        let found = try XCTUnwrap(scan.findStages(in: folder, now: Date()))

        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["broken-new.json", "fresh.json"])
        XCTAssertEqual(found.listed, ["broken-new", "fresh"], "a skipped file is still listed, a swept one is not")
        XCTAssertEqual(found.stages.map(\.session), ["fresh"])
    }

    func testARemovalFailureIsJournaledAgainAfterASweepThatSucceeded() throws {
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        var lines: [String] = []
        var scan = SessionThresholdsScan(log: { event, details in
            if event == "sessionThresholds.notSwept" { lines.append(details["name"] ?? "") }
        })
        try placeOld(1, daysAgo: 31)
        XCTAssertEqual(chmod(folder.path, 0o500), 0)
        _ = scan.findStages(in: folder, now: Date())
        _ = scan.findStages(in: folder, now: Date())
        XCTAssertEqual(chmod(folder.path, 0o700), 0)
        _ = scan.findStages(in: folder, now: Date())
        XCTAssertEqual(try countFiles(), 0)

        try placeOld(2, daysAgo: 31)
        XCTAssertEqual(chmod(folder.path, 0o500), 0)
        _ = scan.findStages(in: folder, now: Date())

        XCTAssertEqual(lines, ["old-0.json", "old-0.json"], "the same reason again after a clean sweep is a new line")
    }

    func testAFolderRemovedAndMadeAgainIsWatchedAgain() throws {
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place(["stage": "saved"], session: "before")
        let watch = SessionThresholds(folder: folder, pollEvery: 100, log: { _, _ in })
        let first = expectation(description: "the first read shows the first session")
        let again = expectation(description: "the session placed in the new folder is read")
        let watched = expectation(description: "a session placed later is seen through the new folder's events")
        for each in [first, again, watched] { each.assertForOverFulfill = false }
        watch.onRead = { found in
            switch found.stages.map(\.session) {
            case ["before"]: first.fulfill()
            case ["after"]: again.fulfill()
            case ["after", "later"]: watched.fulfill()
            default: break
            }
        }
        watch.start()
        defer { watch.stop() }
        wait(for: [first], timeout: 5)

        try FileManager.default.removeItem(at: folder)
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place(["stage": "saved"], session: "after")
        wait(for: [again], timeout: 10)
        try place(["stage": "saved"], session: "later")

        wait(for: [watched], timeout: 10)
    }

    func testAFolderThatCannotBeMadeGivesNoReadAndIsTriedAgain() throws {
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place(["stage": "saved"], session: "earlier")
        let lines = NSLock()
        var toldReasons: [String] = []
        let secondLine = expectation(description: "the same reason is told a second time")
        secondLine.isInverted = true
        let watch = SessionThresholds(folder: folder, retryAfter: 0.5, pollEvery: 100, log: { event, details in
            guard event == "sessionThresholds.unwatched" else { return }
            lines.lock()
            toldReasons.append(details["reason"] ?? "")
            let count = toldReasons.count
            lines.unlock()
            if count == 2 { secondLine.fulfill() }
        })
        var isBroken = false
        let shown = expectation(description: "the first session is read")
        let readWhileBroken = expectation(description: "a read while the folder cannot be made")
        readWhileBroken.isInverted = true
        readWhileBroken.assertForOverFulfill = false
        let back = expectation(description: "once the folder can be made, its session is read")
        for each in [shown, back] { each.assertForOverFulfill = false }
        watch.onRead = { found in
            if isBroken { readWhileBroken.fulfill() }
            switch found.stages.map(\.session) {
            case ["earlier"]: shown.fulfill()
            case ["later"]: back.fulfill()
            default: break
            }
        }
        watch.start()
        defer { watch.stop() }
        wait(for: [shown], timeout: 5)

        isBroken = true
        try FileManager.default.moveItem(at: folder, to: root.appendingPathComponent("moved-away"))
        try Data("x".utf8).write(to: folder)
        wait(for: [secondLine, readWhileBroken], timeout: 2.6)
        isBroken = false
        try FileManager.default.removeItem(at: folder)
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        try place(["stage": "saved"], session: "later")

        wait(for: [back], timeout: 10)
        lines.lock()
        XCTAssertEqual(toldReasons, ["it is a link or not a folder"], "one journal line for one reason, however many tries")
        lines.unlock()
    }

    func testAFolderThatIsALinkIsNotWatchedAndGivesNoRead() throws {
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: elsewhere)
        let told = expectation(description: "the refusal is in the journal")
        let anyRead = expectation(description: "a read through the link")
        anyRead.isInverted = true
        anyRead.assertForOverFulfill = false
        let watch = SessionThresholds(folder: folder, pollEvery: 0.2, log: { event, details in
            if event == "sessionThresholds.unwatched", details["reason"] == "it is a link or not a folder" { told.fulfill() }
        })
        watch.onRead = { _ in anyRead.fulfill() }

        watch.start()
        defer { watch.stop() }

        wait(for: [told, anyRead], timeout: 1.5)
    }

    func testAReadAlreadyOnItsWayToTheMainThreadIsDroppedAfterStop() throws {
        let watch = SessionThresholds(folder: folder, pollEvery: 100, log: { _, _ in })
        let lateRead = expectation(description: "a read handed on after stop")
        lateRead.isInverted = true
        lateRead.assertForOverFulfill = false
        watch.onRead = { _ in lateRead.fulfill() }

        watch.start()
        watch.stop()

        wait(for: [lateRead], timeout: 0.5)
    }

    func testAScanScheduledBeforeStopDoesNotRunAfterIt() throws {
        XCTAssertNil(SessionWindows.findTroubleMakingTheFolder(folder))
        let firstRead = expectation(description: "the first read")
        let lateScan = expectation(description: "the file written before stop was read after it")
        lateScan.isInverted = true
        lateScan.assertForOverFulfill = false
        let watch = SessionThresholds(folder: folder, pollEvery: 100, log: { event, details in
            if event == "sessionThresholds.skipped", details["name"] == "late.json" { lateScan.fulfill() }
        })
        watch.onRead = { _ in firstRead.fulfill() }
        watch.start()
        wait(for: [firstRead], timeout: 5)
        let staged = folder.appendingPathComponent(".tmp-late")
        try Data("{".utf8).write(to: staged)
        XCTAssertEqual(rename(staged.path, folder.appendingPathComponent("late.json").path), 0)
        let settle = expectation(description: "the folder event reaches the watch")
        settle.isInverted = true
        wait(for: [settle], timeout: 0.3)

        watch.stop()

        wait(for: [lateScan], timeout: 1.5)
    }
}
